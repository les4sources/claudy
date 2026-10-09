# Rôles d'accès (Michael, 2026-10-09). Un compte porte un ou plusieurs rôles
# (`User#access_roles`) ; chaque rôle ouvre des SECTIONS de l'app, en lecture ou
# en écriture. Les droits de plusieurs rôles s'additionnent.
#
# Fermé par défaut : un contrôleur qui ne déclare pas sa section
# (`access_section`, cf. `AccessControl`) est réservé aux Sourciers. Ouvrir un
# écran à un autre rôle est donc toujours un geste explicite, ici et dans le
# contrôleur.
#
# À ne pas confondre avec `Role` / `HumanRole` : ce sont les rôles DU JOUR
# (veilleur, ligne de garde…), sans rapport avec ce qu'un compte peut ouvrir.
module Access
  ROLES = {
    "sourcier" => { label: "Sourcier", description: "Accès complet" },
    "communication" => { label: "Communication", description: "Événements et activités, calendrier en lecture" },
    "kid" => { label: "Kid", description: "Calendrier et carte, en lecture seule" },
    "administratif" => { label: "Administratif", description: "Comptes et comptabilité, calendrier en lecture" }
  }.freeze

  ROLE_NAMES = ROLES.keys.freeze

  # Les sections qu'un rôle autre que Sourcier peut ouvrir. `:full` (tout le
  # reste) n'en fait pas partie : il n'appartient qu'aux Sourciers.
  SECTIONS = {
    everyone: "Mon espace (tableau de bord, notifications)",
    calendar: "Agenda",
    events: "Événements et activités",
    accounts: "Comptes",
    accounting: "Comptabilité",
    map: "Carte du domaine"
  }.freeze

  # Ce que chaque rôle ouvre : `:write` (consulter et modifier) ou `:read`
  # (consulter seulement). Le Sourcier a tout, il n'est pas listé.
  GRANTS = {
    "communication" => { calendar: :read, events: :write },
    "kid" => { calendar: :read, map: :read },
    "administratif" => { calendar: :read, accounts: :write, accounting: :write }
  }.freeze

  LEVELS = { read: 1, write: 2 }.freeze

  # Le niveau d'accès que des rôles donnent sur une section : `:write`, `:read`
  # ou `nil`. `:everyone` s'ouvre à tout compte qui a au moins un rôle.
  def self.level(roles, section)
    roles = Array(roles).map(&:to_s) & ROLE_NAMES
    return nil if roles.empty?
    return :write if roles.include?("sourcier")
    return :write if section.to_sym == :everyone

    roles.filter_map { |role| GRANTS.dig(role, section.to_sym) }.max_by { |level| LEVELS[level] }
  end

  def self.label(role) = ROLES.dig(role.to_s, :label) || role.to_s
end
