# == Schema Information
#
# Table name: space_bookings
#
#  id                   :bigint           not null, primary key
#  firstname            :string
#  lastname             :string
#  group_name           :string
#  phone                :string
#  email                :string
#  from_date            :date
#  to_date              :date
#  status               :string
#  tier                 :string
#  payment_status       :string
#  invoice_status       :string
#  contract_status      :string
#  notes                :text
#  token                :string
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  price_cents          :integer
#  payment_method       :string
#  event_id             :bigint
#  public_notes         :text
#  paid_amount_cents    :integer
#  deposit_amount_cents :integer
#  persons              :string
#  arrival_time         :string
#  departure_time       :string
#  option_kitchenware   :boolean          default(FALSE)
#  option_beamer        :boolean          default(FALSE)
#  option_wifi          :boolean          default(FALSE)
#  option_tables        :boolean          default(FALSE)
#  advance_amount_cents :integer
#  deleted_at           :datetime
#
class SpaceBooking < ApplicationRecord
  # PublicActivity
  include PublicActivity::Model
  tracked owner: Proc.new{ |controller, model| controller.current_user rescue nil }

  # Relationships
  has_many :space_reservations, dependent: :destroy
  has_many :spaces, through: :space_reservations
  belongs_to :event, optional: true

  # Versioning
  has_paper_trail
  has_soft_deletion default_scope: true

  monetize :advance_amount_cents, allow_nil: true
  monetize :paid_amount_cents, allow_nil: true
  monetize :deposit_amount_cents, allow_nil: true
  monetize :price_cents, allow_nil: true

  has_rich_text :public_notes

  scope :current_and_future, -> { where("to_date >= ?", Date.today).order(from_date: :asc) }
  scope :past, -> { where("to_date < ?", Date.today).order(from_date: :desc) }

  attr_accessor :space_ids
  attr_accessor :newsletter_subscription
  attr_accessor :duration

  validates_presence_of :firstname,
                        message: "Veuillez préciser un prénom"
  validates_presence_of :from_date,
                        message: "Veuillez préciser la date d'arrivée"
  validates_presence_of :to_date,
                        message: "Veuillez préciser la date de départ"
  validates :email,
            email_format: { message: "L'adresse email fournie ne semble pas valide" },
            allow_blank: true

  before_create :generate_token
  after_update :notify_customer_on_update

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
    )
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

  def filled_duration
    space_reservations&.first&.duration
  end

  def generate_token
    validity = Proc.new { |token| SpaceBooking.where(token: token).first.nil? }
    begin
      generated_token = SecureRandom.hex(8)[0, 8]
      generated_token = generated_token.encode("UTF-8")
    end while validity[generated_token] == false
    self.token = generated_token
  end

  def has_options?
    option_kitchenware? || option_beamer? || option_wifi? || option_tables?
  end

  def name
    "#{firstname} #{lastname}"
  end

  def notify_customer_on_update
    # status notification
    if saved_change_to_status == ["pending", "confirmed"]
      # if booking is confirmed
      SpaceBookingMailer.space_booking_confirmed(self).deliver_now
    elsif saved_change_to_status? && status == "declined"
      # if booking is declined
      SpaceBookingMailer.space_booking_declined(self).deliver_now
    elsif saved_change_to_status? && status == "canceled"
      # if booking is canceled
      SpaceBookingMailer.space_booking_canceled(self).deliver_now
    end
    # payment notification
    if saved_change_to_payment_status? && payment_status == "partially_paid"
      SpaceBookingMailer.space_booking_partially_paid(self).deliver_now
    # elsif saved_change_to_payment_status? && payment_status == "paid"
      # SpaceBookingMailer.space_booking_paid(self).deliver_now
    end
  end

  def notify_customer_on_update
    notify_on_status_change if saved_change_to_status? || saved_change_to_email?
    # notify_on_payment_status_change if saved_change_to_payment_status? || saved_change_to_email?
  end

  # def notify_on_payment_status_change
  #   SpaceBookingMailer.space_booking_partially_paid(self).deliver_now if partially_paid?
  #   SpaceBookingMailer.space_booking_paid(self).deliver_now if paid?
  # end

  def notify_on_status_change
    SpaceBookingMailer.space_booking_confirmed(self).deliver_now if confirmed?
    SpaceBookingMailer.space_booking_declined(self).deliver_now if declined?
    SpaceBookingMailer.space_booking_canceled(self).deliver_now if canceled?
    AdminMailer.space_booking_canceled(self).deliver_now if canceled?
  end

  def paid?
    payment_status == "paid"
  end

  def partially_paid?
    payment_status == "partially_paid"
  end

  def outstanding_balance
    price - paid_amount
  end

  def paid_percent
    paid_amount / price * 100
  rescue
    0
  end

  def paid?
    payment_status == "paid"
  end

  def pending?
    status == "pending"
  end
end
