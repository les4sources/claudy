class ProjectDecorator < ApplicationDecorator
    delegate_all

    def due_date
      l(object.due_date, format: :short) rescue "-"
    end
end
  