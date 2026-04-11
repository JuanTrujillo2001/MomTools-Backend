class BulkUpload < ApplicationRecord
  belongs_to :user

  validates :status, presence: true, inclusion: { in: %w[pending processing completed failed] }
  validates :total, :processed, numericality: { greater_than_or_equal_to: 0 }

  def progress_percentage
    return 0 if total.zero?
    ((processed.to_f / total) * 100).round(2)
  end

  def pending?
    status == 'pending'
  end

  def processing?
    status == 'processing'
  end

  def completed?
    status == 'completed'
  end

  def failed?
    status == 'failed'
  end
end
