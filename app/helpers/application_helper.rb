module ApplicationHelper
  def delete_link(resource)
    link_to "Supprimer",
            send("#{resource.class.name.underscore}_path", resource),
            data: { turbo_method: :delete, turbo_confirm: "Etes-vous sûr(e)?" },
            class: "secondary button"
  end
end
