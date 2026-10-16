class User < ApplicationRecord
  # has_many :ghosts, class_name: "Ghost"
  has_many :groups
  has_many :articles, through: :groups
  has_many :shares, through: dynamic_path
  has_many :posts
  has_many :memberships, through: :groups
end
