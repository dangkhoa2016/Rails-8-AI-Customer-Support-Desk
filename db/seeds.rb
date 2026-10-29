# M1 only: requires M1_SYNTHETIC_DEMO=YES, PostgreSQL, development Rails environment.
raise 'Do not seed production' unless Rails.env.development?
load Rails.root.join('db/seeds/m1_full_business_records.rb')
