class TurboModal::Component < ViewComponent::Base
  # This component is based on:
  # https://www.bearer.com/blog/how-to-build-modals-with-hotwire-turbo-frames-stimulusjs
  # and
  # https://bhserna.com/remote-modals-with-rails-hotwire-and-bootstrap.html

  include Turbo::FramesHelper

  def initialize(title:, width: :lg)
    super
    @title = title
    @modal_classes = set_modal_classes(width)
  end

  def set_modal_classes(width)
    case width
    when :sm
      "sm:w-full sm:max-w-sm"
    when :lg
      "sm:max-w-5xl sm:w-full"
    end
  end

  def turbo_frame_request?
    request.headers['Turbo-Frame']
  end
end
