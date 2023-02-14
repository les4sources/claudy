class Booking < ApplicationRecord
  has_many :reservations, dependent: :destroy
  has_many :rooms, through: :reservations
  belongs_to :lodging, optional: true

  monetize :price_cents, allow_nil: true

  scope :current_and_future, -> { where("to_date >= ?", Date.today).order(from_date: :asc) }
  scope :past, -> { where("to_date < ?", Date.today).order(from_date: :desc) }

  attr_accessor :invoice_wanted
  attr_accessor :room_ids
  attr_accessor :booking_type # lodging || rooms
  attr_accessor :tier_lodgings
  attr_accessor :tier_rooms
  attr_accessor :terms_approval

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

  def canceled?
    status == "canceled"
  end

  def confirmed?
    status == "confirmed"
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

  def name
    "#{firstname} #{lastname}"
  end

  def notify_customer_on_update
    if saved_change_to_status == ["pending", "confirmed"]
      # if booking is confirmed
      BookingMailer.booking_confirmed(self).deliver_now
    elsif saved_change_to_status? && status == "canceled"
      # if booking is canceled
      BookingMailer.booking_canceled(self).deliver_now
    end
  end

  def pending?
    status == "pending"
  end
end
