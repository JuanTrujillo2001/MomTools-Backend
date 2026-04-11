class ClearFileCacheJob < ApplicationJob
  queue_as :default

  def perform
    FileCache.clear_all
  end
end
