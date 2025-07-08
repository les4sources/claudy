# == Schema Information
#
# Table name: customers
#
#  id           :bigint           not null, primary key
#  firstname    :string
#  lastname     :string
#  phone        :string
#  email        :string
#  notes        :text
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  company_name :string
#  vat_number   :string
#  street       :string
#  number       :string
#  box          :string
#  postcode     :string
#  city         :string
#  country      :string           default("Belgique")
#
class Customer < ApplicationRecord

	has_many :stays

	def full_name
    name = "#{firstname} #{lastname}".strip
    name.present? ? name : "(nom non renseigné)"
  end

  def self.find_duplicates
    # Grouper les clients par nom/prénom (insensible à la casse)
    customers_by_name = Customer.all
      .select { |c| c.firstname.present? && c.lastname.present? }
      .group_by { |c| "#{c.firstname.strip.downcase} #{c.lastname.strip.downcase}" }
    
    # Ne garder que les groupes avec plus d'un client
    duplicate_groups = customers_by_name
      .select { |name, customers| customers.length > 1 }
      .map { |name, customers| customers.sort_by(&:created_at) }
    
    duplicate_groups
  end

  def display_info
    info = full_name
    info += " (#{email})" if email.present?
    info += " - #{phone}" if phone.present?
    info += " - #{stays.count} séjour(s)"
    info
  end
end
