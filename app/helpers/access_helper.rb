# Rôles d'accès dans les vues (cf. `Access`, `AccessControl`) : n'afficher que
# ce que le compte connecté peut ouvrir. Le contrôle qui compte reste celui des
# contrôleurs ; ici on évite seulement de montrer une porte fermée.
module AccessHelper
  def section_readable?(section) = access_user&.can_read?(section) || false

  def section_writable?(section) = access_user&.can_write?(section) || false

  # La carte en lecture seule (Kid) : `map_editable?` garde les gestes qui
  # écrivent, `map_edit_guard` désactive un formulaire entier (champs grisés,
  # boutons masqués par `.map-read-only` dans `map.css`). Le serveur refuse de
  # toute façon l'écriture ; ici on évite seulement de la proposer.
  def map_editable? = section_writable?(:map)

  def map_edit_guard(&block)
    content = capture(&block)
    return content if map_editable?

    content_tag(:fieldset, content, disabled: true, class: "contents", data: { map_read_only: true })
  end

  private

  # Hors requête authentifiable (previews Lookbook, rendus hors contrôleur), pas
  # de Warden : personne n'est connecté, rien ne s'affiche.
  def access_user
    current_user if request&.env&.key?("warden")
  end
end
