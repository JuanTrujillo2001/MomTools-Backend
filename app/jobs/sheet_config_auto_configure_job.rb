class SheetConfigAutoConfigureJob < ApplicationJob
  queue_as :default

  def perform(catalog_id)
    catalog = Catalog.find_by(id: catalog_id)
    return unless catalog

    sheet_configs = catalog.sheet_configs.order(:sheet_name)

    sheet_configs.each do |sc|
      next unless Array(sc.code_columns).empty? && Array(sc.price_columns).empty?

      Rails.logger.info("[SheetConfigAutoConfigureJob] auto_config_start catalog_id=#{catalog.id} sheet_config_id=#{sc.id} sheet_name=\"#{sc.sheet_name}\"")
      res = SheetConfigAutoConfigurator.new(sc).call
      Rails.logger.info("[SheetConfigAutoConfigureJob] auto_config_done catalog_id=#{catalog.id} sheet_config_id=#{sc.id} success=#{res[:success]} error=\"#{res[:error]}\"")
    end
  rescue StandardError => e
    Rails.logger.error("[SheetConfigAutoConfigureJob] error catalog_id=#{catalog_id} #{e.class} #{e.message}")
    raise
  end
end
