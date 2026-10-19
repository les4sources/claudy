class ProjectDecorator < ApplicationDecorator
    delegate_all

    STATUS_CLASSES = {
      "active" => "bg-teal-50 text-teal-700 ring-teal-600/20",
      "paused" => "bg-amber-50 text-amber-800 ring-amber-600/20",
      "done" => "bg-gray-50 text-gray-600 ring-gray-500/10"
    }.freeze

    def due_date
      l(object.due_date, format: :short) rescue "-"
    end

    def status_badge
      h.content_tag(:span, object.status_label,
                    class: "inline-flex items-center whitespace-nowrap rounded-md px-1.5 py-0.5 text-xs font-medium ring-1 ring-inset #{STATUS_CLASSES.fetch(object.status, STATUS_CLASSES['done'])}")
    end
end
