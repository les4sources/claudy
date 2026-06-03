# == Schema Information
#
# Table name: booking_page_views
#
#  id         :bigint           not null, primary key
#  booking_id :bigint           not null
#  ip_address :string
#  user_agent :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Une consultation de la page web privée (à jeton) d'une réservation par un·e
# client·e. Sert à savoir si les client·es consultent leur page de réservation.
# Voir issue #16.
class BookingPageView < ApplicationRecord
  belongs_to :booking
end
