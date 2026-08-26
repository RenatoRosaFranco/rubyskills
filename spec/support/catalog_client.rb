# frozen_string_literal: true

require "digest"

module RubySkillsSpec
  # In-memory {RubySkills::Registry::Client} stand-in for resolution tests.
  class CatalogClient
    def initialize
      @releases = {}
    end

    def add(name, version, checksum: nil, yanked: false, published: true)
      @releases[name] ||= {}
      @releases[name][version.to_s] = {
        version: version.to_s,
        checksum: checksum || Digest::SHA256.hexdigest("#{name}@#{version}"),
        yanked: yanked,
        published: published,
        download_url: download_url_for(name, version)
      }
      self
    end

    def get_skill(name)
      releases = @releases.fetch(name) { raise not_found("Skill not found") }
      available = releases.values.select { |release| available?(release) }

      RubySkills::Registry::Skill.new(
        name: name,
        summary: nil,
        latest_version: highest(available),
        categories: [],
        versions: available.map { |release| release[:version] },
        downloads: 0
      )
    end

    def get_version(name, version)
      releases = @releases.fetch(name) { raise not_found("Version not found") }
      release = releases[version.to_s]
      raise not_found("Version not found") if release.nil? || !release[:published]

      RubySkills::Registry::Version.new(
        name: name,
        version: release[:version],
        checksum: release[:checksum],
        manifest: {},
        published_at: release[:published] ? "2026-08-01T00:00:00Z" : nil,
        yanked: release[:yanked],
        download_url: release[:download_url]
      )
    end

    private

    def available?(release)
      release[:published] && !release[:yanked]
    end

    def highest(available)
      return if available.empty?

      available.map { |release| release[:version] }.max_by { |value|
        Gem::Version.new(value)
      }
    end

    def download_url_for(name, version)
      "https://rubyskills.org/api/v1/skills/#{name}/versions/#{version}/download"
    end

    def not_found(message)
      RubySkills::Registry::Error.new(message, code: "not_found", status: 404)
    end
  end
end
