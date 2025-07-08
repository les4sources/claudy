class CustomerDecorator < ApplicationDecorator
  delegate_all

  def self.collection_decorator_class
    PaginatingDecorator
  end

  def display_name
    if company_name.present?
      company_name
    else
      full_name
    end
  end

  def full_name
    name = "#{lastname} #{firstname}".strip
    name.present? ? name : "(nom non renseigné)"
  end

  def formatted_address
    return nil if street.blank? && city.blank?
    
    address_parts = []
    
    # Ligne 1: Rue, numéro, boîte
    street_line = []
    street_line << street if street.present?
    street_line << number if number.present?
    street_line << "boîte #{box}" if box.present?
    address_parts << street_line.join(", ") if street_line.any?
    
    # Ligne 2: Code postal et ville
    city_line = []
    city_line << postcode if postcode.present?
    city_line << city if city.present?
    address_parts << city_line.join(" ") if city_line.any?
    
    # Ligne 3: Pays
    address_parts << country if country.present? && country != "Belgique"
    
    address_parts.join("<br>").html_safe
  end

  def contact_person_info
    return nil if company_name.blank?
    full_name if firstname.present? || lastname.present?
  end

  def confirmed_stays_count
    object.stays.where(status: 'confirmed').count
  end

  def total_revenue
    total_payments = object.stays.joins(:payments)
                          .where(payments: { status: ['paid', 'pending'] })
                          .sum('payments.amount_cents')
    h.number_to_currency(total_payments / 100.0)
  end

  def contact_info
    info_parts = []
    info_parts << email if email.present?
    info_parts << phone if phone.present?
    info_parts.join(' • ')
  end

  def latest_stay
    object.stays.order(start_date: :desc).first
  end

  def stays_status_summary
    confirmed = confirmed_stays_count
    total = object.stays.count
    pending = object.stays.where(status: 'pending').count
    
    parts = []
    parts << "#{confirmed} confirmé#{'s' if confirmed > 1}" if confirmed > 0
    parts << "#{pending} en attente" if pending > 0
    parts << "#{total - confirmed - pending} autre#{'s' if (total - confirmed - pending) > 1}" if (total - confirmed - pending) > 0
    
    parts.join(', ')
  end
end 