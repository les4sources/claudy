module ApplicationHelper
  def delete_link(resource)
    link_to "Supprimer",
            send("#{resource.class.name.underscore}_path", resource),
            method: :delete,
            data: { confirm: "Êtes-vous sûr?" },
            class: "secondary button"
  end
end
