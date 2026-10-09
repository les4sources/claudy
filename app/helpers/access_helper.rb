# Rôles d'accès dans les vues (cf. `Access`, `AccessControl`) : n'afficher que
# ce que le compte connecté peut ouvrir. Le contrôle qui compte reste celui des
# contrôleurs ; ici on évite seulement de montrer une porte fermée.
module AccessHelper
  def section_readable?(section) = current_user&.can_read?(section) || false

  def section_writable?(section) = current_user&.can_write?(section) || false
end
