namespace :file_cache do
  desc "Clear tmp/file_cache directory"
  task clear: :environment do
    FileCache.clear_all
  end
end
