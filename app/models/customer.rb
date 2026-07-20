# == Schema Information
#
# Table name: customers
#
#  id                 :bigint           not null, primary key
#  first_name         :string
#  last_name          :string
#  email              :citext
#  phone              :string
#  customer_type      :string           default("individual"), not null
#  organization_name  :string
#  vat_number         :string
#  peppol_id          :string
#  address_line       :string
#  address_zip        :string
#  address_city       :string
#  address_country    :string
#  language           :string           default("fr"), not null
#  stripe_customer_id :string
#  marketing_consent  :boolean          default(FALSE), not null
#  nps_eligible       :boolean          default(FALSE), not null
#  human_id           :bigint
#  deleted_at         :datetime
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#
class Customer < ApplicationRecord
  CUSTOMER_TYPES = %w[individual organization].freeze
  LANGUAGES = %w[fr nl en].freeze

  # Email of the conventional catch-all customer that collects every legacy
  # booking without an exploitable email. Re-ventilated later via the merge flow.
  CATCH_ALL_EMAIL = "client@les4sources.be".freeze
  # Fourre-tout par OTA (2026-07-20) : les clients Airbnb/Booking.com n'ont pas
  # d'email — plutôt qu'engorger le fourre-tout générique, chaque OTA a le sien.
  # Un client fourre-tout ne doit JAMAIS voir d'historique inter-séjours sur la
  # page publique (contrairement aux clients standards, à terme).
  OTA_CATCH_ALL_EMAILS = {
    "airbnb"        => "client-airbnb@les4sources.be",
    "bookingdotcom" => "client-booking@les4sources.be"
  }.freeze
  CATCH_ALL_EMAILS = ([CATCH_ALL_EMAIL] + OTA_CATCH_ALL_EMAILS.values).freeze

  belongs_to :human, optional: true
  has_many :stays, dependent: :restrict_with_error
  # Payments are derived read-only through the stays graph (Payment schema is
  # untouched — Payment.booking_id stays NOT NULL). No payment.stay_id FK.
  has_many :payments, through: :stays

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :notes

  before_validation :normalize_email
  before_validation :normalize_phone

  validates :email,
            presence: { message: "Veuillez préciser une adresse email" },
            email_format: { message: "L'adresse email fournie ne semble pas valide" }
  validate :email_unique_among_live
  validates :customer_type,
            inclusion: { in: CUSTOMER_TYPES, message: "Type de client invalide" }
  validates :language,
            inclusion: { in: LANGUAGES, message: "Langue invalide" }
  validates :organization_name,
            presence: { message: "Veuillez préciser le nom de l'organisation" },
            if: :organization?

  scope :search, ->(query) {
    return all if query.blank?
    q = "%#{query.strip}%"
    where("email ILIKE :q OR first_name ILIKE :q OR last_name ILIKE :q OR organization_name ILIKE :q", q: q)
  }

  # Compteurs de séjours calculés EN SQL (aucun N+1) pour la liste admin :
  #   - `stays_count`          : nombre de séjours VIVANTS (soft-delete exclu) ;
  #   - `upcoming_stays_count` : séjours vivants à venir, même sémantique que le
  #     scope `Stay.current_and_future` (`departure_date >= aujourd'hui`).
  # Le LEFT JOIN porte lui-même le filtre `stays.deleted_at IS NULL` (le
  # default_scope de Stay ne s'applique pas à une jointure manuelle). GROUP BY
  # sur la PK ⇒ `customers.*` est sélectionnable (dépendance fonctionnelle PG).
  scope :with_stay_counts, -> {
    today = connection.quote(Date.current)
    select(
      "customers.*",
      "COUNT(stays.id) AS stays_count",
      "COUNT(stays.id) FILTER (WHERE stays.departure_date >= #{today}) AS upcoming_stays_count"
    )
      .joins("LEFT JOIN stays ON stays.customer_id = customers.id AND stays.deleted_at IS NULL")
      .group("customers.id")
  }

  # Single point of email normalization, reused by the legacy migration.
  def self.normalize_email(raw)
    return nil if raw.nil?
    raw.to_s.strip.downcase.presence
  end

  # Is this raw email usable as a real customer key? Blank or format-invalid
  # emails route to the catch-all (AC-4/AC-37); a format-valid address — even an
  # OTA relay like x@guest.airbnb.com — is exploitable and gets its own
  # Customer (AC-49). Single deterministic rule.
  def self.exploitable_email?(raw)
    normalized = normalize_email(raw)
    return false if normalized.blank?
    ValidatesEmailFormatOf.validate_email_format(normalized).nil?
  end

  def individual?
    customer_type == "individual"
  end

  def organization?
    customer_type == "organization"
  end

  def catch_all?
    CATCH_ALL_EMAILS.include?(email)
  end

  # Nombre de séjours VIVANTS rattachés. `stays` porte le default_scope de
  # soft-deletion de Stay : les séjours soft-deletés (restes d'assainissement)
  # sont déjà exclus, donc ne comptent pas.
  def live_stays_count
    stays.count
  end

  # Un client n'est supprimable que s'il n'a AUCUN séjour vivant. C'est la seule
  # garde qui compte : les `payments` sont dérivés `through: :stays` (zéro séjour
  # vivant ⟹ zéro paiement vivant), et les Booking legacy ne sont reliés au
  # Customer QUE via le graphe des séjours (stay_items). Aucun rattachement
  # vivant ne subsiste donc en dehors des séjours.
  def deletable?
    live_stays_count.zero?
  end

  # Message expliquant pourquoi la suppression est refusée (nil si supprimable).
  def deletion_blocker
    return if deletable?
    "#{live_stays_count} séjour(s) vivant(s) rattaché(s)"
  end

  def name
    if organization? && organization_name.present?
      organization_name
    else
      [first_name, last_name].compact_blank.join(" ").presence || email
    end
  end

  # Available on the bare model (not just the decorator) so controllers can use
  # it for breadcrumbs before decoration. The decorator overrides with the same
  # semantics for view contexts.
  def display_name
    name
  end

  private

  def normalize_email
    self.email = self.class.normalize_email(email)
  end

  def normalize_phone
    return if phone.blank?
    digits = phone.gsub(/[^\d+]/, "")
    self.phone = digits.presence
  end

  # citext unique index is partial (live rows only); enforce the same rule at the
  # model layer so the validation error surfaces cleanly (AC-3) without relying on
  # a DB exception. Case/whitespace insensitivity comes from normalize_email.
  def email_unique_among_live
    return if email.blank?
    scope = Customer.where(email: email)
    scope = scope.where.not(id: id) if persisted?
    errors.add(:email, "Cette adresse email est déjà utilisée") if scope.exists?
  end
end
