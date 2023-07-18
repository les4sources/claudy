class TaskDecorator < ApplicationDecorator
    delegate_all

    decorates_association :human

    def avatars
      buffer = ActiveSupport::SafeBuffer.new
      zindex = object.humans.count * 10 - 10
      object.humans.each do |human|
        buffer << h.image_tag(human.photo_url(:thumb), class: "relative z-#{zindex} inline-block h-8 w-8 rounded-full ring-2 ring-white")
        zindex = zindex - 10
      end
      html = h.content_tag(:div, buffer, class: "isolate flex -space-x-2 overflow-hidden")
      html.html_safe
    end

    def avatars_with_name
      html = ""
      object.humans.each do |human|
        html << h.content_tag(:div, class: "block mb-2 flex-shrink-0") do
          h.content_tag(:div, class: "flex items-center") do
            h.content_tag(:div, h.image_tag(human.photo_url(:thumb), class: "inline-block h-9 w-9 rounded-full")) +
            h.content_tag(:div, class: "ml-3") do
              h.content_tag(:p, human.name, class: "text-sm font-medium text-gray-700") +
              h.link_to("Afficher le profil", h.human_path(human), class: "text-xs font-medium text-gray-500")
            end
          end
        end
      end
      h.raw(html)
    end

    def due_date
      l(object.due_date, format: :short) rescue "-"
    end
end
  