# Class that controls all blog features of the site

require 'erb'
require 'mysql2'
require './lib/blog_post.rb'
require './lib/http_server.rb'

class BlogController
  attr_reader :page_name

  TEMPLATES = {
    homepage: ERB.new(File.read './public/templates/blog_home.erb'),
    archive:  ERB.new(File.read './public/templates/blog_archive.erb'),
    new_post: ERB.new(File.read './public/templates/blog_post_form.erb'),
    post:     ERB.new(File.read './public/templates/blog_post.erb')
  }

  def initialize
    @page_name = "PJ's Site"
    @sql_client = Mysql2::Client.new(username: 'blogapp', password: ENV['mysql_blogapp_password'], database: 'blog')
  end

  def respond(path)
    if path == '/'
      render_homepage
    elsif path == '/archive'
      render_archive
    elsif path == '/new_post'
      render_new_post
    else
      render_post(path[1..-1])
    end
  end

  def render_homepage
    recent_posts = recent_posts(5)
    HTTPServer.generic_html(TEMPLATES[:homepage].result(binding))
  end

  def render_archive
    archive = fetch_archive
    HTTPServer.generic_html(TEMPLATES[:archive].result(binding))
  end

  def render_new_post
    HTTPServer.generic_html(TEMPLATES[:new_post].result(binding))
  end

  def render_post(slug)
    data = stmt_from_slug.execute(slug).first
    if data.nil?
      HTTPServer.generic_404
    else
      post = BlogPost.new(data)
      HTTPServer.generic_html(TEMPLATES[:post].result(binding))
    end
  end

  def recent_posts(count=65536)
    stmt_n_most_recent.execute(count)
  end

  def fetch_archive
    archive = {}
    active_year, active_month = nil, nil
    recent_posts.each do |post|
      ts = post['post_timestamp']
      if active_year != ts.year
        archive[ts.year] = {}
        active_year = ts.year
      end
      if active_month != ts.strftime('%B')
        archive[active_year][ts.strftime('%B')] = []
        active_month = ts.strftime('%B')
      end
      archive[active_year][active_month] << post
    end
    archive
  end

  def next_post_id
    last_post = stmt_last_post_id.execute.first
    if last_post.nil?
      return 0
    else
      return 1 + stmt_last_post_id.execute.first['post_id']
    end
  end

  def insert_new_post(values)
    stmt_insert_new_post.execute(
      next_post_id,
      @sql_client.escape(values['title']),
      @sql_client.escape(values['slug']),
      @sql_client.escape(values['body'])
    )
  end

  def validate_post(values)
    all_posts = recent_posts
    errors = {}
    unless values['password'] == ENV['blogapp_author_password']
      errors[:password] = "Incorrect password!"
    end
    if !slug_valid?(values['slug'])
      errors[:slug] = "Invalid slug!"
    elsif all_posts.any? {|post| post['post_slug'] == values['slug']}
      errors[:slug] = "Slug already in use!"
    end
    if all_posts.any? {|post| post['post_title'] == values['title']}
      errors[:title] = "Title already in use!"
    end
    errors
  end

  def slug_valid?(slug)
    regexp = /^[A-Za-z0-9]+(?:[A-Za-z0-9_-]+[A-Za-z0-9]){0,255}$/
    !(regexp =~ slug).nil?
  end

  private

  def stmt_from_slug
    @stmt_from_slug ||= @sql_client.prepare <<~SQL
      SELECT post_title, post_body, post_timestamp
      FROM posts
      WHERE post_slug=?
    SQL
  end

  def stmt_n_most_recent
    @stmt_n_most_recent ||= @sql_client.prepare <<~SQL
      SELECT post_slug, post_title, post_timestamp
      FROM posts
      ORDER BY post_timestamp DESC
      LIMIT ?
    SQL
  end

  def stmt_last_post_id
    @stmt_last_post_id ||= @sql_client.prepare <<~SQL
      SELECT post_id
      FROM posts
      ORDER BY post_id DESC
      LIMIT 1
    SQL
  end

  def stmt_insert_new_post
    @stmt_insert_new_post ||= @sql_client.prepare <<~SQL
      INSERT INTO posts(post_id, post_title, post_slug, post_body)
      VALUES(?, ?, ?, ?)
    SQL
  end
end