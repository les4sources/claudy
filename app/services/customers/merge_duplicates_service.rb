class Customers::MergeDuplicatesService < ServiceBase
  attr_reader :master_customer, :duplicate_customers

  def run(master_customer_id:, duplicate_ids:)
    context = {
      master_customer_id: master_customer_id,
      duplicate_ids: duplicate_ids
    }

    catch_error(context: context) do
      run!(master_customer_id: master_customer_id, duplicate_ids: duplicate_ids)
    end
  end

  def run!(master_customer_id:, duplicate_ids:)
    validate_parameters(master_customer_id, duplicate_ids)
    load_customers(master_customer_id, duplicate_ids)
    merge_customers
    true
  end

  private

  def validate_parameters(master_customer_id, duplicate_ids)
    if master_customer_id.blank?
      set_error_message("Il faut sélectionner un client maître")
      return false
    end

    if duplicate_ids.empty?
      set_error_message("Il faut sélectionner au moins un client à supprimer")
      return false
    end

    if duplicate_ids.include?(master_customer_id.to_s)
      set_error_message("Le client maître ne peut pas être dans la liste des doublons à supprimer")
      return false
    end

    true
  end

  def load_customers(master_customer_id, duplicate_ids)
    @master_customer = Customer.find(master_customer_id)
    @duplicate_customers = Customer.where(id: duplicate_ids)

    if @duplicate_customers.count != duplicate_ids.length
      set_error_message("Certains clients à supprimer n'ont pas été trouvés")
      return false
    end

    true
  end

  def merge_customers
    ActiveRecord::Base.transaction do
      # Transférer tous les séjours vers le client maître
      @duplicate_customers.each do |duplicate_customer|
        duplicate_customer.stays.update_all(customer_id: @master_customer.id)
        
        # Fusionner les informations manquantes du client maître
        merge_customer_info(duplicate_customer)
      end

      # Supprimer les clients doublons
      @duplicate_customers.destroy_all

      # Logger l'opération
      Rails.logger.info "Fusion de clients - Maître: #{@master_customer.id}, Supprimés: #{@duplicate_customers.pluck(:id)}"
    end
  end

  def merge_customer_info(duplicate_customer)
    # Fusionner les informations manquantes
    @master_customer.email = duplicate_customer.email if @master_customer.email.blank? && duplicate_customer.email.present?
    @master_customer.phone = duplicate_customer.phone if @master_customer.phone.blank? && duplicate_customer.phone.present?
    @master_customer.company_name = duplicate_customer.company_name if @master_customer.company_name.blank? && duplicate_customer.company_name.present?
    @master_customer.vat_number = duplicate_customer.vat_number if @master_customer.vat_number.blank? && duplicate_customer.vat_number.present?
    @master_customer.street = duplicate_customer.street if @master_customer.street.blank? && duplicate_customer.street.present?
    @master_customer.number = duplicate_customer.number if @master_customer.number.blank? && duplicate_customer.number.present?
    @master_customer.box = duplicate_customer.box if @master_customer.box.blank? && duplicate_customer.box.present?
    @master_customer.postcode = duplicate_customer.postcode if @master_customer.postcode.blank? && duplicate_customer.postcode.present?
    @master_customer.city = duplicate_customer.city if @master_customer.city.blank? && duplicate_customer.city.present?
    @master_customer.country = duplicate_customer.country if @master_customer.country.blank? && duplicate_customer.country.present?
    
    # Combiner les notes
    if duplicate_customer.notes.present?
      if @master_customer.notes.present?
        @master_customer.notes += "\n\n--- Fusionné depuis client #{duplicate_customer.id} ---\n#{duplicate_customer.notes}"
      else
        @master_customer.notes = duplicate_customer.notes
      end
    end

    @master_customer.save!
  end
end 