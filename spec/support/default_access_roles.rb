# Les specs créent leurs comptes à la main (`User.create!(email:, password:)`)
# sans rôle d'accès. Elles décrivent l'équipe telle qu'elle était avant les
# rôles (2026-10-09) : des Sourciers, comme la migration a fait de tous les
# comptes existants. Une spec qui teste les rôles les passe explicitement
# (`access_roles: [...]`, `[]` compris) et n'est pas touchée.
module DefaultAccessRolesInSpecs
  def initialize(attributes = nil, &block)
    super
    explicit = attributes.respond_to?(:key?) && (attributes.key?(:access_roles) || attributes.key?("access_roles"))
    self.access_roles = ["sourcier"] unless explicit
  end
end

User.prepend(DefaultAccessRolesInSpecs)
