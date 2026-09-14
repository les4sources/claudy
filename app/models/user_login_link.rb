# Lien de connexion à usage unique pour un compte Devise (issue #306).
#
# Un SECOND chemin d'entrée, au choix de l'utilisateur : saisir son adresse,
# recevoir un lien, cliquer, être connecté. Le mot de passe reste disponible et
# inchangé — on ajoute une porte, on n'en condamne aucune.
#
# LE JETON N'EST JAMAIS STOCKÉ EN CLAIR. Seul son digest SHA256 l'est, préfixé
# pour qu'un digest de cette table ne puisse jamais servir ailleurs. Une fuite
# de la base ne donne donc aucun lien utilisable.
#
# UN SEUL LIEN VIVANT À LA FOIS. Émettre brûle les précédents : un lien demandé
# deux fois ne laisse pas deux portes ouvertes derrière soi.
#
# Ce modèle copie l'esprit de `PortalOtp` sans le toucher : population
# différente (`User` et non `Customer`), mécanisme différent (lien et non code
# à 6 chiffres), session différente (Devise et non `sign_in_portal`).
# == Schema Information
#
# Table name: user_login_links
#
#  id           :bigint           not null, primary key
#  consumed_at  :datetime
#  expires_at   :datetime         not null
#  token_digest :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  user_id      :bigint           not null
#
# Indexes
#
#  index_user_login_links_on_token_digest            (token_digest)
#  index_user_login_links_on_user_id_and_created_at  (user_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class UserLoginLink < ApplicationRecord
  VALIDITY = 15.minutes

  # Rate-limit d'émission : sans lui, n'importe qui peut bombarder de mails une
  # adresse connue. Les lignes consommées comptent aussi — brûler un lien ne
  # remet pas le compteur à zéro.
  MAX_ISSUES_PER_HOUR = 5

  belongs_to :user

  validates :token_digest, :expires_at, presence: true

  scope :usable, -> { where(consumed_at: nil).where(expires_at: Time.current..) }
  scope :recent, -> { where(created_at: 1.hour.ago..) }

  def self.throttled?(user)
    return true if user.nil?

    where(user_id: user.id).recent.count >= MAX_ISSUES_PER_HOUR
  end

  # Émet un lien pour cet utilisateur et retourne [lien, jeton_en_clair]. Le
  # jeton en clair ne repasse plus jamais par ici : il part dans l'e-mail, et
  # c'est tout.
  def self.issue!(user)
    where(user_id: user.id).usable.update_all(consumed_at: Time.current)

    token = SecureRandom.urlsafe_base64(32)
    link = create!(user: user,
                   token_digest: digest(token),
                   expires_at: Time.current + VALIDITY)
    [ link, token ]
  end

  # Le lien utilisable correspondant à ce jeton, ou nil. La comparaison passe
  # par `secure_compare` : un `==` sur un digest fuit sa réponse par le temps
  # qu'il met à la donner.
  def self.find_usable(token)
    candidate = token.to_s
    return nil if candidate.blank?

    attendu = digest(candidate)

    usable.where(token_digest: attendu).find do |link|
      ActiveSupport::SecurityUtils.secure_compare(link.token_digest, attendu)
    end
  end

  def self.digest(token)
    Digest::SHA256.hexdigest("user-login-link:#{token}")
  end

  def consume!
    update!(consumed_at: Time.current)
  end

  def expired?(now = Time.current) = expires_at <= now

  def consumed? = consumed_at.present?
end
