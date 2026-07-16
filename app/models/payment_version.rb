# Version PaperTrail dédiée aux Payment (issue #52).
#
# Stockée dans `payment_versions` (item_id UUID) plutôt que dans la table
# `versions` partagée (item_id bigint), car la PK de Payment est un UUID.
# Voir `Payment#has_paper_trail versions: { class_name: "PaymentVersion" }`.
class PaymentVersion < PaperTrail::Version
  self.table_name = :payment_versions
end
