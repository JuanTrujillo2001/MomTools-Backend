class BulkUploadsController < ApplicationController
  before_action :authenticate_user!

  def show
    bulk_upload = current_user.bulk_uploads.find(params[:id])
    
    render json: {
      id: bulk_upload.id,
      status: bulk_upload.status,
      total: bulk_upload.total,
      processed: bulk_upload.processed,
      progress_percentage: bulk_upload.progress_percentage,
      results: bulk_upload.results,
      created_at: bulk_upload.created_at,
      updated_at: bulk_upload.updated_at
    }
  end
end
