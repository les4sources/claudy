class Stay < ApplicationRecord
  
  belongs_to :customer
  
  has_many :stay_items
  has_many :lodgings, through: :stay_items, source: :item, source_type: 'Lodging'
  has_many :rooms, through: :stay_items, source: :item, source_type: 'Room'
  has_many :beds, through: :stay_items, source: :item, source_type: 'Bed'
  has_many :experiences, through: :stay_items, source: :item, source_type: 'Experience'
  has_many :rental_items, through: :stay_items, source: :item, source_type: 'RentalItem'
  has_many :products, through: :stay_items, source: :item, source_type: 'Product'


  accepts_nested_attributes_for :customer



  scope :current_and_future, -> { where("end_date >= ?", Date.today).order(start_date: :asc) }
  scope :past, -> { where("end_date < ?", Date.today).order(start_date: :desc) }



  def generate_token
    validity = Proc.new { |token| Stay.where(token: token).first.nil? }
    begin
      generated_token = SecureRandom.hex(8)[0, 8]
      generated_token = generated_token.encode("UTF-8")
    end while validity[generated_token] == false
    self.token = generated_token
  end


  def name
    "#{firstname} #{lastname}"
  end

  def nights_count
    (self.end_date - self.start_date).to_i
  end

  def canceled?
    status == "canceled"
  end

  def confirmed?
    status == "confirmed"
  end

  def current?
    (start_date..end_date).cover?(Date.today)
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

end