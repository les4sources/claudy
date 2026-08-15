# L'IBAN d'un client, appris à chaque rapprochement validé par un humain.
#
# C'est le mécanisme le plus rentable du lot : au deuxième séjour d'un client
# récurrent, son virement se rattache tout seul. Et il ne s'apprend que sur
# validation humaine — un IBAN deviné une fois deviendrait une erreur répétée.
class CustomerBankAccount < ApplicationRecord
  has_paper_trail
  has_soft_deletion default_scope: true

  belongs_to :customer

  validates :iban, presence: true, uniqueness: { scope: :customer_id }

  before_validation :normalize_iban

  def self.remember!(customer:, iban:, holder_name: nil)
    return nil if customer.blank? || iban.blank?

    account = find_or_initialize_by(customer: customer, iban: iban.to_s.gsub(/\s+/, "").upcase)
    account.holder_name = holder_name.presence || account.holder_name
    account.matches_count += 1
    account.last_matched_at = Time.current
    account.save!
    account
  end

  # Rend TOUS les clients connus pour cet IBAN. Un compte joint, ou une
  # association et son trésorier, peuvent en partager un : l'appelant doit voir
  # l'ambiguïté au lieu de recevoir un client choisi au hasard.
  def self.customers_for(iban)
    return [] if iban.blank?

    where(iban: iban.to_s.gsub(/\s+/, "").upcase).includes(:customer).map(&:customer).compact.uniq
  end

  private

  def normalize_iban
    self.iban = iban.to_s.gsub(/\s+/, "").upcase
  end
end
