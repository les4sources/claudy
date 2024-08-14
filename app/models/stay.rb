# == Schema Information
#
# Table name: stays
#
#  id                :bigint           not null, primary key
#  user_id           :bigint           not null
#  start_date        :date
#  end_date          :date
#  status            :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  platform          :string
#  adults            :integer
#  children          :integer
#  babies            :integer
#  estimated_arrival :string
#  departure_time    :string
#  token             :string
#  customer_id       :bigint           not null
#  deleted_at        :datetime
#  comments          :text
#  notes             :text
#
class Stay < ApplicationRecord
  belongs_to :customer, optional: true
  
  has_many :stay_items
  has_many :lodgings, through: :stay_items, source: :item, source_type: 'Lodging'
  has_many :rooms, through: :stay_items, source: :item, source_type: 'Room'
  has_many :beds, through: :stay_items, source: :item, source_type: 'Bed'
  has_many :experiences, through: :stay_items, source: :item, source_type: 'Experience'
  has_many :rental_items, through: :stay_items, source: :item, source_type: 'RentalItem'
  has_many :products, through: :stay_items, source: :item, source_type: 'Product'
  has_many :spaces, through: :stay_items, source: :item, source_type: 'Space'

  has_many :payment_requests

  accepts_nested_attributes_for :customer

  has_soft_deletion default_scope: true

  has_paper_trail


  scope :current_and_future, -> { where("end_date >= ? and draft = ? ", Date.today, false).order(start_date: :asc) }
  scope :past, -> { where("end_date < ? and draft = ? ", Date.today, false).order(start_date: :desc) }



  def self.generate_token
    validity = Proc.new { |token| Stay.where(token: token).first.nil? }
    begin
      generated_token = SecureRandom.hex(8)[0, 8]
      generated_token = generated_token.encode("UTF-8")
    end while validity[generated_token] == false
    generated_token
  end


  def name
    "#{self.customer.firstname} #{self.customer.lastname}"
  end

  def nights_count
    (self.end_date - self.start_date).to_i
  end

  def canceled?
    status == StayStatus::CANCELED
  end

  def confirmed?
    status == StayStatus::CONFIRMED
  end

  def declined?
    status == StayStatus::DECLINED
  end

  def pending?
    status == StayStatus::PENDING
  end

  def current?
    (start_date..end_date).cover?(Date.today)
  end


  def from_airbnb?
    platform == "airbnb"
  end

  def from_web?
    platform == "web"
  end

  def has_options?
    self.experiences.any? || self.spaces.any?
  end


  def payment_status
    if payment_requests.all? { |pr| pr.paid? }
      PaymentRequest::PAYMENT_PAID
    elsif payment_requests.any? { |pr| pr.partially_paid? }
      PaymentRequest::PAYMENT_PARTIALLY_PAID
    else
      PaymentRequest::PAYMENT_PENDING
    end
  end

  def total_remaining_amount
    payment_requests.to_a.sum {|pr| (pr.remaining_amount)}
  end

  def total_payments_received
    payment_requests.to_a.sum {|pr| (pr.total_paid/100)}
  end

  # Calculer le montant total demandé pour le séjour (somme des payment_requests)
  def total_requested_amount
    payment_requests.sum(:amount_cents)
  end

  # Calculer le montant total de la réservation basé sur les stay_items
  def total_reservation_amount
    stay_items.to_a.sum { |item| (item.total_price/100) }
  end

  def rooms_by_date
    rooms_hash = dates_with_items(stay_items.where(item_type: StayItem::ROOM))
    
    # if lodgings have been booked, the rooms shall be the rooms that belongs to the lodging
    rooms_from_lods = []
    stay_items.where(item_type: StayItem::LODGING).each do |lod|
      Lodging.find(lod.item_id).rooms.each do |room|
        rooms_from_lods << StayItem.new(stay_id: lod.stay_id, 
                                        start_date: lod.start_date, 
                                        end_date: lod.end_date,
                                        item_id: room.id,
                                        item_type: StayItem::ROOM)
      end
    end
  
    rooms_hash = rooms_hash.merge(dates_with_items(rooms_from_lods))
    rooms_hash
  end

  def experiences_by_date
    dates_with_items(stay_items.where(item_type: StayItem::EXPERIENCE))
  end

  def products_by_date
    dates_with_items(stay_items.where(item_type: StayItem::PRODUCT))
  end

  def spaces_by_date
    dates_with_items(stay_items.where(item_type: StayItem::SPACE))
  end

  def rental_items_by_date
    dates_with_items(stay_items.where(item_type: StayItem::RENTAL_ITEM))
  end

  def dates_with_items(_stay_items)
    reservation_hash = Hash.new { |hash, key| hash[key] = [] }

    _stay_items.each do |stay_item|
      (stay_item.start_date..stay_item.end_date).each do |date|
        reservation_hash[date] << stay_item.item
      end
    end
    reservation_hash.sort.to_h
  end


end
