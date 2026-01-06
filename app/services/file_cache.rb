class FileCache
  CACHE_DIR = Rails.root.join("tmp", "file_cache")
  DEFAULT_TTL = 1.day

  class << self
    def fetch(blob, ttl: DEFAULT_TTL)
      ensure_cache_dir
      cache_path = path_for(blob)

      if valid_cache?(cache_path, ttl)
        Rails.logger.info("[FileCache] hit blob_key=#{blob.key}")
        return cache_path
      end

      Rails.logger.info("[FileCache] miss blob_key=#{blob.key}, downloading...")
      download_to_cache(blob, cache_path)
      cache_path
    end

    def invalidate(blob)
      cache_path = path_for(blob)
      if File.exist?(cache_path)
        File.delete(cache_path)
        Rails.logger.info("[FileCache] invalidated blob_key=#{blob.key}")
      end
    end

    def clear_expired(ttl: DEFAULT_TTL)
      return unless Dir.exist?(CACHE_DIR)

      expired_count = 0
      Dir.glob(CACHE_DIR.join("*")).each do |file|
        if File.file?(file) && File.mtime(file) < ttl.ago
          File.delete(file)
          expired_count += 1
        end
      end
      Rails.logger.info("[FileCache] cleared #{expired_count} expired files") if expired_count > 0
      expired_count
    end

    private

    def ensure_cache_dir
      FileUtils.mkdir_p(CACHE_DIR) unless Dir.exist?(CACHE_DIR)
    end

    def path_for(blob)
      safe_key = blob.key.gsub("/", "_")
      safe_checksum = blob.checksum.to_s.gsub(/[^0-9A-Za-z\-_.]/, "_")
      CACHE_DIR.join("#{safe_key}_#{safe_checksum}#{File.extname(blob.filename.to_s)}")
    end

    def valid_cache?(path, ttl)
      File.exist?(path) && File.mtime(path) > ttl.ago
    end

    def download_to_cache(blob, cache_path)
      # Remove old versions of same blob (different checksum)
      safe_key = blob.key.gsub("/", "_")
      Dir.glob(CACHE_DIR.join("#{safe_key}_*")).each do |old_file|
        File.delete(old_file) if old_file != cache_path.to_s
      end

      File.open(cache_path, "wb") do |file|
        file.write(blob.download)
      end
    end
  end
end
