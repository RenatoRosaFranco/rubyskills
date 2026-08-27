# frozen_string_literal: true

require "rubygems/package"
require "stringio"
require "zlib"

module RubySkills
  module Artifact
    # Writes a deterministic ustar archive and gzip-compresses it.
    #
    # mtime, UID/GID, and user/group names are fixed so two builds of the
    # same bytes produce an identical +.rskill+.
    #
    # @api private
    # @since 0.1.0
    module Archive
      FILE_MODE = 0o644
      MTIME = 0
      UID = 0
      GID = 0
      UNAME = ""
      GNAME = ""

      # @param entries [Array<(String, String)>] +[archive_path, binary_content]+
      # @return [String] gzip-compressed tar bytes
      def self.pack(entries)
        gzip(tar(entries))
      end

      # @param entries [Array<(String, String)>]
      # @return [String]
      def self.tar(entries)
        io = StringIO.new(+"", "wb")
        writer = Writer.new(io)
        entries.each do |name, content|
          writer.add_file_simple(name, FILE_MODE, content.bytesize) do |file|
            file.write(content)
          end
        end
        writer.close
        io.string
      end
      private_class_method :tar

      # @param bytes [String]
      # @return [String]
      def self.gzip(bytes)
        buffer = StringIO.new(+"", "wb")
        gz = Zlib::GzipWriter.new(buffer, Zlib::DEFAULT_COMPRESSION)
        gz.mtime = MTIME
        gz.write(bytes)
        gz.close
        buffer.string
      end
      private_class_method :gzip

      # `Gem::Package::TarWriter` with frozen tar metadata.
      class Writer < Gem::Package::TarWriter
        # @param name [String]
        # @param mode [Integer]
        # @param size [Integer]
        # @return [self]
        def add_file_simple(name, mode, size)
          check_closed

          header_name, prefix = split_name(name)
          header = Gem::Package::TarHeader.new(
            name: header_name,
            mode: mode,
            size: size,
            prefix: prefix,
            mtime: MTIME,
            uid: UID,
            gid: GID,
            uname: UNAME,
            gname: GNAME,
            typeflag: "0",
            linkname: ""
          ).to_s

          @io.write(header)
          os = BoundedStream.new(@io, size)
          yield os if block_given?
          @io.write("\0" * (size - os.written))
          @io.write("\0" * ((512 - (size % 512)) % 512))

          self
        end
      end
    end
  end
end
