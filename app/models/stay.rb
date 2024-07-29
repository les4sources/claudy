class Stay < ApplicationRecord
  
  belongs_to :customer
  has_many :stay_items, dependent: :destroy

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

end