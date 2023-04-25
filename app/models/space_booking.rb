class SpaceBooking < ApplicationRecord
  has_many :space_reservations, dependent: :destroy
  has_many :spaces, through: :space_reservations
  belongs_to :event, optional: true

  has_paper_trail

  monetize :advance_amount_cents, allow_nil: true
  monetize :paid_amount_cents, allow_nil: true
  monetize :deposit_amount_cents, allow_nil: true
  monetize :price_cents, allow_nil: true

  has_rich_text :public_notes

  scope :current_and_future, -> { where("to_date >= ?", Date.today).order(from_date: :asc) }
  scope :past, -> { where("to_date < ?", Date.today).order(from_date: :desc) }

  attr_accessor :invoice_wanted
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

  def canceled?
    status == "canceled"
  end

  def confirmed?
    status == "confirmed"
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
    elsif saved_change_to_payment_status? && payment_status == "paid"
      SpaceBookingMailer.space_booking_paid(self).deliver_now
    end
  end

  def notify_customer_on_update
    notify_on_status_change if saved_change_to_status? || saved_change_to_email?
    notify_on_payment_status_change if saved_change_to_payment_status? || saved_change_to_email?
  end

  def notify_on_payment_status_change
    SpaceBookingMailer.space_booking_partially_paid(self).deliver_now if partially_paid?
    SpaceBookingMailer.space_booking_paid(self).deliver_now if paid?
  end

  def notify_on_status_change
    SpaceBookingMailer.space_booking_confirmed(self).deliver_now if confirmed?
    SpaceBookingMailer.space_booking_declined(self).deliver_now if declined?
    SpaceBookingMailer.space_booking_canceled(self).deliver_now if canceled?
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
