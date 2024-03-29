# == Schema Information
#
# Table name: bookings
#
#  id                 :bigint           not null, primary key
#  firstname          :string
#  lastname           :string
#  phone              :string
#  email              :string
#  from_date          :date
#  to_date            :date
#  status             :string
#  adults             :integer
#  children           :integer
#  payment_status     :string
#  payment_method     :string
#  bedsheets          :boolean
#  towels             :boolean
#  notes              :text
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  price_cents        :integer
#  invoice_status     :string
#  contract_status    :string
#  estimated_arrival  :string
#  option_babysitting :boolean
#  option_partyhall   :boolean
#  option_bread       :boolean
#  comments           :text
#  tier               :string
#  lodging_id         :bigint
#  option_discgolf    :boolean
#  shown_price_cents  :integer          default(0), not null
#  token              :string
#  platform           :string
#  group_name         :string
#  babies             :integer          default(0)
#  public_notes       :text
#  departure_time     :string
#  option_pizza_party :boolean
#  deleted_at         :datetime
#  wifi               :boolean          default(FALSE)
#
class Booking < ApplicationRecord
  # PublicActivity
  include PublicActivity::Model
  tracked owner: Proc.new{ |controller, model| controller.current_user rescue nil }

  # Relationships
  has_many :reservations, dependent: :destroy
  has_many :rooms, through: :reservations
  has_many :payments, inverse_of: :booking do
    def persisted
      reject { |payment| !payment.persisted? }
    end
  end

  belongs_to :lodging, optional: true

  monetize :price_cents, allow_nil: true

  has_paper_trail
  has_soft_deletion default_scope: true

  has_rich_text :public_notes

  scope :current_and_future, -> { where("to_date >= ?", Date.today).order(from_date: :asc) }
  scope :past, -> { where("to_date < ?", Date.today).order(from_date: :desc) }

  attr_accessor :invoice_wanted
  attr_accessor :room_ids
  attr_accessor :booking_type # lodging || rooms
  attr_accessor :tier_lodgings
  attr_accessor :tier_rooms
  attr_accessor :terms_approval
  attr_accessor :newsletter_subscription

  validates_presence_of :firstname,
                        message: "Veuillez préciser votre prénom"
  validates_presence_of :from_date,
                        message: "Veuillez préciser votre date d'arrivée"
  validates_presence_of :to_date,
                        message: "Veuillez préciser votre date de départ"
  validates :email,
            email_format: { message: "L'adresse email fournie ne semble pas valide" },
            allow_blank: true
  validates :adults, 
            numericality: { greater_than: 0, message: "Veuillez préciser le nombre d'adultes" }
  # validates_presence_of :lastname,
  #                       message: "Veuillez préciser votre nom"
  # validates_presence_of :email,
  #                       message: "Veuillez préciser votre adresse email"
  # validates_presence_of :payment_method,
  #                       message: "Veuillez spécifier votre moyen de paiement"

  before_create :generate_token
  after_update :notify_customer_on_update

  accepts_nested_attributes_for :payments, 
                                allow_destroy: true,
                                reject_if: lambda { |attributes| attributes['amount'].to_f.zero? }

  def self.search(query)
    return none if query.blank?
    if query.match?(/\A-?\d+(\.\d+)?\z/) # numeric
      normalized_price_query = query.gsub(',', '.')
      price_query = normalized_price_query.to_f.round(2) * 100
    else
      price_query = -9999
    end
    where(
      "group_name ILIKE :query OR email ILIKE :query OR firstname ILIKE :query OR lastname ILIKE :query OR token ILIKE :query OR price_cents = :price_query", 
      query: "%#{query}%", 
      price_query: price_query
    ).order(from_date: :desc)
  end

  def beds_count
    adults + children
  end

  def canceled?
    status == "canceled"
  end

  def confirmed?
    status == "confirmed"
  end

  def current?
    (from_date..to_date).cover?(Date.today)
  end

  def declined?
    status == "declined"
  end

  def from_airbnb?
    platform == "airbnb"
  end

  def from_web?
    platform == "web"
  end

  def generate_token
    validity = Proc.new { |token| Booking.where(token: token).first.nil? }
    begin
      generated_token = SecureRandom.hex(8)[0, 8]
      generated_token = generated_token.encode("UTF-8")
    end while validity[generated_token] == false
    self.token = generated_token
  end

  def has_options?
    option_partyhall? || option_pizza_party? || option_bread? || option_babysitting? || option_discgolf?
  end

  def name
    "#{firstname} #{lastname}"
  end

  def nights_count
    (self.to_date - self.from_date).to_i
  end

  def notify_customer_on_update
    notify_on_status_change if saved_change_to_status? || saved_change_to_email?
    # notify_on_payment_status_change if saved_change_to_payment_status? || saved_change_to_email?
  end

  # def notify_on_payment_status_change
  #   BookingMailer.booking_partially_paid(self).deliver_now if partially_paid?
  #   BookingMailer.booking_paid(self).deliver_now if paid?
  # end

  def notify_on_status_change
    BookingMailer.booking_confirmed(self).deliver_now if confirmed?
    BookingMailer.booking_declined(self).deliver_now if declined?
    BookingMailer.booking_canceled(self).deliver_now if canceled?
    AdminMailer.booking_canceled(self).deliver_now if canceled?
  end

  def paid?
    payment_status == "paid"
  end

  def partially_paid?
    payment_status == "partially_paid"
  end

  def pending?
    status == "pending"
  end

  def undefined_price?
    tier == "non défini"
  end

  def set_payment_status
    if self.payments.paid.sum(:amount_cents) >= self.price_cents
      status = "paid"
    elsif self.payments.paid.sum(:amount_cents) > 0.0
      status = "partially_paid"
    else
      status = "pending"
    end
    self.update(payment_status: status)
  end
end
