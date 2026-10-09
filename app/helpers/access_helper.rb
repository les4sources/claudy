# Rôles d'accès dans les vues (cf. `Access`, `AccessControl`) : n'afficher que
# ce que le compte connecté peut ouvrir. Le contrôle qui compte reste celui des
# contrôleurs ; ici on évite seulement de montrer une porte fermée.
module AccessHelper
  def section_readable?(section) = access_user&.can_read?(section) || false

  def section_writable?(section) = access_user&.can_write?(section) || false

  private

  # Hors requête authentifiable (previews Lookbook, rendus hors contrôleur), pas
  # de Warden : personne n'est connecté, rien ne s'affiche.
  def access_user
    current_user if request&.env&.key?("warden")
  end
end
