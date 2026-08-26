# frozen_string_literal: true

require "fileutils"
require "pathname"

module RubySkills
  # Writes a file via a same-directory tempfile and rename.
  #
  # @api private
  module AtomicFile
    class << self
      # @param path [String, Pathname]
      # @param content [String]
      # @return [Pathname]
      def write(path, content)
        destination = Pathname.new(path)
        FileUtils.mkdir_p(destination.dirname)
        tmp = destination.dirname.join(".#{destination.basename}.#{Process.pid}.tmp")
        tmp.write(content)
        tmp.rename(destination)
        destination
      rescue StandardError
        tmp.unlink if defined?(tmp) && tmp.exist?
        raise
      end
    end
  end
end
