# frozen_string_literal: true

require "open3"

module Switchyard
  class ProcessRunner
    def exec(*args)
      Kernel.exec(*args)
    end

    def system(*args)
      Kernel.system(*args)
    end

    def capture(*args)
      Open3.capture2e(*args)
    end
  end
end
