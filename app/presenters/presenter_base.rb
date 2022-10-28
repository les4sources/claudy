class PresenterBase
  include ActionView::Helpers::FormTagHelper
  include ActionView::Helpers::AssetUrlHelper
  include ActionView::Helpers::NumberHelper
  include ActionView::Helpers::TranslationHelper
  include ActionView::Helpers::UrlHelper
  include ActionView::Helpers::TagHelper
  # include Webpacker::Helper
  include ActionView::Context
  include ApplicationHelper
  include UiHelper
  include Rails.application.routes.url_helpers

  private

  # This prevents an error with the link_to helper
  def controller
    nil
  end

  def render_icon(icon)
    paths = ["app/views/"]
    icon.split("/").each_with_index do |path, index|
      if index+1 == icon.split("/").count
        paths << "_#{path}.html.slim"
      else
        paths << "#{path}/"
      end
    end
    path = Rails.root.join(*paths).to_s
    raw(File.read(path))
  end

  def safe_html(&block)
    block.call.html_safe
  end
end
