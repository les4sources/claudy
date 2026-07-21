# Code à usage unique du portail client (epic #126, Phase 2).
#
# Le code n'est JAMAIS stocké en clair : seul son digest l'est. On ne peut donc
# pas le relire depuis la base — seulement vérifier une saisie.
#
# Un code vit 15 minutes et tolère 5 tentatives ; au-delà, il est brûlé et le
# client doit en redemander un.
class PortalOtp < ApplicationRecord
  CODE_LENGTH = 6
  VALIDITY = 15.minutes
  MAX_ATTEMPTS = 5

  validates :email, :code_digest, :expires_at, presence: true

  scope :usable, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }
  scope :for_email, ->(email) { where(email: email.to_s.strip.downcase) }

  # Rate-limit d'émission (best practice OTP) : pas plus de MAX_ISSUES_PER_HOUR
  # codes émis par heure et par email — sinon n'importe qui peut bombarder de
  # mails une adresse connue. Les lignes consommées comptent aussi (elles
  # restent en base), donc brûler un code ne remet pas le compteur à zéro.
  MAX_ISSUES_PER_HOUR = 5

  def self.throttled?(email)
    for_email(email).where("created_at > ?", 1.hour.ago).count >= MAX_ISSUES_PER_HOUR
  end

  # Émet un code pour cet email et retourne [otp, code_en_clair]. Les codes
  # précédents encore vivants sont brûlés : un seul code valide à la fois.
  def self.issue!(email)
    normalized = email.to_s.strip.downcase
    for_email(normalized).usable.update_all(consumed_at: Time.current)

    code = SecureRandom.random_number(10**CODE_LENGTH).to_s.rjust(CODE_LENGTH, "0")
    otp = create!(email: normalized,
                  code_digest: digest(code),
                  expires_at: Time.current + VALIDITY)
    [otp, code]
  end

  # Vérifie une saisie pour cet email. Retourne l'OTP consommé, ou nil.
  # Chaque échec consomme une tentative ; à MAX_ATTEMPTS, le code est brûlé.
  def self.verify(email, code)
    otp = for_email(email).usable.order(created_at: :desc).first
    return nil if otp.nil?

    if ActiveSupport::SecurityUtils.secure_compare(otp.code_digest, digest(code.to_s.strip))
      otp.update!(consumed_at: Time.current)
      return otp
    end

    otp.attempts += 1
    otp.consumed_at = Time.current if otp.attempts >= MAX_ATTEMPTS
    otp.save!
    nil
  end

  def self.digest(code)
    Digest::SHA256.hexdigest("portal-otp:#{code}")
  end

  def expired?(now = Time.current) = expires_at <= now

  def consumed? = consumed_at.present?
end
