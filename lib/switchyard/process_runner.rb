# frozen_string_literal: true

require "open3"
require "pty"

module Switchyard
  class ProcessRunner
    PTY_COMMANDS = [
      %w[railway environment edit]
    ].freeze

    def exec(*args)
      Kernel.exec(*args)
    end

    def system(*args)
      Kernel.system(*args)
    end

    def capture(*args)
      return capture_pty(*args) if pty_command?(args)

      Open3.capture2e(*args)
    end

    private

    def pty_command?(args)
      PTY_COMMANDS.any? { |prefix| args.first(prefix.length) == prefix }
    end

    def capture_pty(*args)
      output = +""
      status = nil
      PTY.spawn(*args) do |reader, _writer, pid|
        begin
          reader.each { |line| output << line }
        rescue Errno::EIO
          nil
        end
        _, status = Process.wait2(pid)
      end
      [output, status]
    end
  end
end
