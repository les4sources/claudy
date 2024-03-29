require 'will_paginate/view_helpers/link_renderer'
require 'will_paginate/view_helpers/action_view'

module Pagination
  # https://github.com/mislav/will_paginate/blob/v3.3.1/lib/will_paginate/view_helpers/link_renderer.rb
  class TailwindUIPaginationRenderer < WillPaginate::ActionView::LinkRenderer
    CLASSES = { container: 'relative z-0 inline-flex rounded-md shadow-sm -space-x-px' }.freeze

    def container_attributes
      { class: CLASSES[:container] }
    end

    def page_number(page)
      render('will_paginate/page_number',
             { locals: { page: page, current_page: current_page, classes: CLASSES,
                         target: url(page) } })
    end

    def gap
      render('will_paginate/gap')
    end

    def previous_page
      num = @collection.current_page > 1 && (@collection.current_page - 1)
      render('will_paginate/previous',
             { locals: { page: num, target: url(num), text: @options[:previous_label] } })
    end

    def next_page
      num = @collection.current_page < total_pages && (@collection.current_page + 1)
      render('will_paginate/next',
             { locals: { page: num, target: url(num), text: @options[:next_label] } })
    end

    private

    def render(template, options = {})
      # Setting layout to false bypasses Warden
      # ref: https://github.com/heartcombo/devise/issues/4271#issuecomment-704182728
      ApplicationController.render({ template: template, layout: false }.merge(options))
    end
  end
end