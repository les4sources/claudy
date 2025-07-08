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
#  customer_id       :bigint
#  deleted_at        :datetime
#  comments          :text
#  notes             :text
#  draft             :boolean          default(TRUE)
#  payment_status    :string
#  invoice_status    :string
#  group_name        :string
#  public_notes      :text
#  final_price_cents :integer          default(0), not null
#
class Stay < ApplicationRecord
  # PublicActivity
  include PublicActivity::Model
  tracked owner: Proc.new{ |controller, model| controller.current_user rescue nil }
  
  belongs_to :customer, optional: true
  
  has_many :stay_items
  has_many :lodgings, through: :stay_items, source: :item, source_type: 'Lodging'
  has_many :rooms, through: :stay_items, source: :item, source_type: 'Room'
  has_many :beds, through: :stay_items, source: :item, source_type: 'Bed'
  has_many :experiences, through: :stay_items, source: :item, source_type: 'Experience'
  has_many :rental_items, through: :stay_items, source: :item, source_type: 'RentalItem'
  has_many :products, through: :stay_items, source: :item, source_type: 'Product'
  has_many :spaces, through: :stay_items, source: :item, source_type: 'Space'

  has_many :payments, inverse_of: :stay do
        def persisted
          reject { |payment| !payment.persisted? }
         end
        end
  has_many :stay_item_dates

  accepts_nested_attributes_for :customer
  accepts_nested_attributes_for :payments, 
                                allow_destroy: true,
                                reject_if: lambda { |attributes| attributes['amount'].to_f.zero? }

  has_soft_deletion default_scope: true

  has_paper_trail

  monetize :final_price_cents, allow_nil: true


  scope :current_and_future, -> { where("end_date >= ? and draft = ? ", Date.today, false).order(start_date: :asc) }
  scope :past, -> { where("end_date < ? and draft = ? ", Date.today, false).order(start_date: :desc) }
  scope :draft_excluded, -> { where("draft = ?", false)}

  def self.generate_token
    validity = Proc.new { |token| Stay.where(token: token).first.nil? }
    begin
      generated_token = SecureRandom.hex(5)[0, 5]
      generated_token = generated_token.encode("UTF-8")
    end while validity[generated_token] == false
    generated_token
  end

  def name
    "#{self.customer&.firstname} #{self.customer&.lastname}"
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

  def paid?
    payment_status == "paid"
  end

  def partially_paid?
    payment_status == "partially_paid"
  end

  def pending?
    status == "pending"
  end

  def set_payment_status
    if self.payments.paid.sum(:amount_cents) >= self.final_price_cents
      status = "paid"
    elsif self.payments.paid.sum(:amount_cents) > 0.0
      status = "partially_paid"
    else
      status = "pending"
    end
    self.update(payment_status: status)
  end

  def total_remaining_amount
    self.final_price.to_f - total_payments_received
  end

  def total_payments_received
    payments.paid.to_a.sum {|p| (p.amount.to_f)}
  end

  # Calculer le montant total de la réservation basé sur le prix de chaque stay_items
  def total_reservation_amount
    stay_items.to_a.sum { |item| item.calculated_price.to_f }
  end

  def build_booked_item
    self.stay_items.each do |item|
      case item.item_type 
      when StayItem::LODGING
        # the lodging is booked
        StayItemDate.build_item_dates(self.id, item, item.item_id, StayItem::LODGING, true)
        # the rooms of that lodgings are booked as well'
        lod = Lodging.find(item.item_id)
        lod.rooms.each do |room|
          StayItemDate.build_item_dates(self.id, item, room.id, StayItem::ROOM)
          # the beds of the rooms are marked as booked as well
          room.beds.each do |bed|
            StayItemDate.build_item_dates(self.id, item, bed.id, StayItem::BED)
          end
        end
      when StayItem::ROOM
        # the room is booked
        StayItemDate.build_item_dates(self.id, item, item.item_id, StayItem::ROOM, true)
        # the corresponding lodging is marked as booked as well
        room = Room.find(item.item_id)
        # the beds of this room are booked as well
        room.beds.each do |bed|
            StayItemDate.build_item_dates(self.id, item, bed.id,  StayItem::BED)
        end
      when StayItem::BED
        # the bed is booked
        StayItemDate.build_item_dates(self.id, item, item.item_id, StayItem::BED, true)
      when StayItem::EXPERIENCE
        StayItemDate.build_item_dates(self.id, item, item.item_id, StayItem::EXPERIENCE, true)
      when StayItem::SPACE
        StayItemDate.build_item_dates(self.id, item, item.item_id, StayItem::SPACE, true)
      end
    end
  rescue ActiveRecord::RecordNotUnique => e
    raise e
  end

  def rooms_by_date
    rooms_hash = Stay.items_grouped_by_date(stay_items.where(item_type: StayItem::ROOM))
    
    # if lodgings have been booked, the rooms shall also be the rooms that belongs to the lodging
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
    rooms_hash = rooms_hash.merge(Stay.items_grouped_by_date(rooms_from_lods))
    rooms_hash
  end

  def experiences_by_date
    Stay.items_grouped_by_date(stay_items.where(item_type: StayItem::EXPERIENCE))
  end

  def products_by_date
    Stay.items_grouped_by_date(stay_items.where(item_type: StayItem::PRODUCT))
  end

  def spaces_by_date
    Stay.items_grouped_by_date(stay_items.where(item_type: StayItem::SPACE))
  end

  def rental_items_by_date
    Stay.items_grouped_by_date(stay_items.where(item_type: StayItem::RENTAL_ITEM))
  end

  def self.items_grouped_by_date(_stay_items)
    reservation_hash = Hash.new { |hash, key| hash[key] = [] }

    _stay_items.each do |stay_item|
      (stay_item.start_date..stay_item.end_date).each do |date|
        reservation_hash[date] << stay_item.item
      end
    end
    reservation_hash.sort.to_h
  end

  def self.stay_items_grouped_by_date(_stay_items)
    reservation_hash = Hash.new { |hash, key| hash[key] = [] }

    _stay_items.each do |stay_item|
      (stay_item.start_date..stay_item.end_date).each do |date|
        reservation_hash[date] << stay_item
      end
    end
    reservation_hash.sort.to_h
  end
end
