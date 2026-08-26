# frozen_string_literal: true

module RubySkillsSpec
  # Isolates +~/.config/ruby-skills+ behind +XDG_CONFIG_HOME+.
  module UserConfigHome
    # @yieldparam directory [Pathname] +$XDG_CONFIG_HOME/ruby-skills+
    # @return [void]
    def with_user_config_home
      Dir.mktmpdir("ruby-skills-xdg-") do |dir|
        previous_xdg = ENV.fetch("XDG_CONFIG_HOME", nil)
        previous_url = ENV.fetch("RUBY_SKILLS_REGISTRY_URL", nil)
        previous_token = ENV.fetch("RUBY_SKILLS_API_TOKEN", nil)
        ENV["XDG_CONFIG_HOME"] = dir
        ENV.delete("RUBY_SKILLS_REGISTRY_URL")
        ENV.delete("RUBY_SKILLS_API_TOKEN")

        begin
          yield Pathname.new(dir).join("ruby-skills")
        ensure
          restore_env("XDG_CONFIG_HOME", previous_xdg)
          restore_env("RUBY_SKILLS_REGISTRY_URL", previous_url)
          restore_env("RUBY_SKILLS_API_TOKEN", previous_token)
        end
      end
    end

    private

    # @param key [String]
    # @param value [String, nil]
    # @return [void]
    def restore_env(key, value)
      if value.nil?
        ENV.delete(key)
      else
        ENV[key] = value
      end
    end
  end
end
