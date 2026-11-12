# Les specs créent leurs comptes à la main (`User.create!(email:, password:)`)
# sans rôle d'accès. Elles décrivent l'équipe telle qu'elle était avant les
# rôles (2026-10-09) : des Sourciers, comme la migration a fait de tous les
# comptes existants. Une spec qui teste les rôles les passe explicitement
# (`access_roles: [...]`, `[]` compris) et n'est pas touchée.
#
# Depuis le 2026-11-12, la Comptabilité est réservée aux Administratifs et la
# Situation financière aux Sourciers : le compte par défaut porte les deux,
# pour que les specs écrites avant gardent l'accès à tout.
module DefaultAccessRolesInSpecs
  def initialize(attributes = nil, &block)
    super
    explicit = attributes.respond_to?(:key?) && (attributes.key?(:access_roles) || attributes.key?("access_roles"))
    self.access_roles = %w[sourcier administratif] unless explicit
  end
end

User.prepend(DefaultAccessRolesInSpecs)
