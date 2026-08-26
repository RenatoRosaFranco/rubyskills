# frozen_string_literal: true

require "rbconfig"

module RubySkills
  # Opens a URL in the user's default browser when possible.
  #
  # Disabled when +RUBY_SKILLS_NO_BROWSER=1+. Failure to launch is ignored;
  # the CLI still prints the URL.
  #
  # @api private
  module Browser
    # @param url [String]
    # @return [Boolean] whether a launcher was invoked
    def self.open(url)
      return false if ENV["RUBY_SKILLS_NO_BROWSER"].to_s == "1"
      return false if url.to_s.empty?

      command = launcher
      return false unless command

      system(*command, url.to_s, out: File::NULL, err: File::NULL)
    end

    # @return [Array<String>, nil]
    def self.launcher
      os = RbConfig::CONFIG["host_os"].to_s
      return %w[open] if os.include?("darwin")
      return %w[xdg-open] if os.match?(/linux|bsd/)
      return ["cmd", "/c", "start"] if os.match?(/mswin|mingw|cygwin/)

      nil
    end
  end
end
