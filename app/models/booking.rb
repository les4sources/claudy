class Booking < ApplicationRecord
  has_many :reservations, dependent: :destroy
  has_many :rooms, through: :reservations
  belongs_to :lodging

  monetize :price_cents, allow_nil: true

  default_scope -> { order(from_date: :desc) }

  attr_accessor :invoice_wanted
  attr_accessor :room_ids
  attr_accessor :booking_type # lodging || rooms

  validates_presence_of :firstname,
                        message: "Veuillez préciser votre prénom"
  validates_presence_of :lastname,
                        message: "Veuillez préciser votre nom"
  validates_presence_of :email,
                        message: "Veuillez préciser votre adresse email"
  validates_presence_of :from_date,
                        message: "Veuillez préciser votre date d'arrivée"
  validates_presence_of :to_date,
                        message: "Veuillez préciser votre date de départ"
  validates_presence_of :adults,
                        message: "Veuillez préciser le nombre d'adultes"
  validates_presence_of :children,
                        message: "Veuillez préciser le nombre d'enfants"
  validates_presence_of :payment_method,
                        message: "Veuillez spécifier votre moyen de paiement"

  before_create :generate_token

  def canceled?
    status == "canceled"
  end

  def confirmed?
    status == "confirmed"
  end

  def generate_token
    validity = Proc.new { |token| Booking.where(token: token).first.nil? }
    begin
      generated_token = SecureRandom.hex(8)[0, 8]
      generated_token = generated_token.encode("UTF-8")
    end while validity[generated_] == false
    self.token = generated_token
  end

  def name
    "#{firstname} #{lastname}"
  end

  def pending?
    status == "pending"
  end
end
