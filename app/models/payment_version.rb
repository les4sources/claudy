# Version PaperTrail dédiée aux Payment (issue #52).
#
# Stockée dans `payment_versions` (item_id UUID) plutôt que dans la table
# `versions` partagée (item_id bigint), car la PK de Payment est un UUID.
# Voir `Payment#has_paper_trail versions: { class_name: "PaymentVersion" }`.
# == Schema Information
#
# Table name: payment_versions
#
#  id             :bigint           not null, primary key
#  event          :string           not null
#  item_type      :string           not null
#  object         :text
#  object_changes :text
#  whodunnit      :string
#  created_at     :datetime
#  item_id        :uuid             not null
#
# Indexes
#
#  index_payment_versions_on_item_type_and_item_id  (item_type,item_id)
#
class PaymentVersion < PaperTrail::Version
  self.table_name = :payment_versions
end
