require "pathname"
require "fileutils"
require "yaml"
require "erb"
require "redcarpet"

SRC_DIR = "src"
DST_DIR = "dist"

DEFAULT_TEMPLATE = ERB.new(File.read("templates/default.html.erb"))
POST_TEMPLATE = ERB.new(File.read("templates/post.html.erb"))
INDEX_TEMPLATE = ERB.new(File.read("templates/index.html.erb"))

# Explore the subtree within this directory, creating target files along the
# way.
def visit(dir)
  # Create the directory.
  Dir.mkdir(target_path(dir))

  # Collect links to put on index later.
  links = []

  # Convert .md files to .html files.
  render_source_files = Dir.glob(File.join(dir, "*.md"))
  posts = render_source_files.collect{|source| Post.load_file(source)}

  posts_with_date = posts.select{|post| not post.date.nil?}.sort_by{|post| post.date}
  unless posts_with_date.empty?
    posts_with_date[0..-2].each_with_index do |post, i|
      later_post = posts_with_date[i+1]
      post.next_post = later_post
      later_post.prev_post = post
    end
  end

  posts.each do |post|
    rendered_post = POST_TEMPLATE.result(post.get_binding)
    page = Page.new(title: post.title, body: rendered_post)
    result = DEFAULT_TEMPLATE.result(page.get_binding)
    f = File.open(target_path(post.source), "w")
    f.write(result)

    links << Link.new(
      url: post.url,
      title: post.title,
      date: post.date,
    )
  end

  # Copy other files.
  entries = Dir.glob(File.join(dir, "*"))
  source_subdirs = entries.select{|e| File.directory?(e)}
  mirror_source_files = entries - render_source_files - source_subdirs

  mirror_source_files.each do |source|
    FileUtils.cp(source, target_path(source))
    links << Link.new(url: File.basename(target_path(source)))
  end

  # Recursively visit subdirectories.
  source_subdirs.each do |subdir|
    visit(subdir)
    links << Link.new(url: File.basename(target_path(subdir)))
  end

  # Create index if it's not already there.
  index_target_path = File.join(target_path(dir), "index.html")
  unless File.exist?(index_target_path)
    index = Index.new(
      links: links,
      dirname: File.join(target_url(target_path(dir)), "/"),
    )
    result = INDEX_TEMPLATE.result(index.get_binding)
    page = Page.new(title: index.dirname, body: result)
    result = DEFAULT_TEMPLATE.result(page.get_binding)
    f = File.open(index_target_path, "w")
    f.write(result)
  end
end

# Given a target path, return the relative path from the top-level target
# directory as if it were an absolute path.
def target_url(target)
  File.join("/", Pathname.new(target).relative_path_from(Pathname.new(DST_DIR)).to_s)
end

# Given a source path, return the path to the target.
def target_path(source)
  source.
    sub(/^#{SRC_DIR}/, "#{DST_DIR}").
    sub(/\.md$/, ".html")
end

def path_crumbs(cwd)
  crumbs = []
  crumbs << Crumb.new(url: ".", name: File.basename(cwd))
  cwd = File.dirname(cwd)
  depth = 1
  while cwd != "/"
    crumbs << Crumb.new(url: File.join([".."] * depth), name: File.basename(cwd))
    cwd = File.dirname(cwd)
    depth += 1
  end
  crumbs.reverse
end

class Post
  attr_reader :source, :title, :date, :content
  attr_accessor :next_post, :prev_post
  def initialize(args)
    @source = args[:source]
    @title = args[:title]
    @date = args[:date]
    @content = args[:content]
  end
  def url
    File.basename(target_path(@source))
  end
  def crumbs
    cwd = target_url(target_path(@source))
    # Pop the filename, leaving the directory
    cwd = File.dirname(cwd)
    path_crumbs(cwd)
  end
  def get_binding
    binding
  end
  def self.load_file(source)
    metadata, content_raw = parse_front_matter(source)
    post_file = PostFile.new(source: source)
    content = ERB.new(content_raw).result(post_file.get_binding)
    content = Redcarpet::Markdown.new(Redcarpet::Render::HTML).render(content)
    Post.new(
      source: source,
      title: metadata["title"],
      date: metadata["date"],
      content: content,
    )
  end
end

def parse_front_matter(source)
  f = File.open(source)
  raise "file does not start with \"---\\n\"" unless f.readline == "---\n"
  pieces = f.read.split("---\n", 2)
  raise "metadata does not end with \"---\\n\"" unless pieces.length == 2
  metadata = YAML.load(pieces[0])
  return metadata, pieces[1]
end

# PostFile contains the API available to post authors.
class PostFile
  attr_reader :source
  def initialize(args)
    @source = args[:source]
  end

  # returns the final transformed url of the given source file.
  # TODO make this sensitive to the source
  def url_for(path)
    raise "no file at path: #{path}" unless File.exists?(File.expand_path(path, File.dirname(@source)))
    target_path(path)
  end

  def get_binding
    binding
  end
end

# Page represents a complete webpage.
class Page
  attr_reader :title, :body
  def initialize(args)
    @title = args[:title]
    @body = args[:body]
  end

  def get_binding
    binding
  end
end

class Link
  attr_reader :url, :date
  def initialize(args)
    @url = args[:url]
    @title = args[:title]
    @date = args[:date]
  end

  def title
    return @title if @title
    return @url
  end
end

class Index
  attr_reader :links, :dirname
  def initialize(args)
    @links = args[:links]
    @dirname = args[:dirname]
  end
  def crumbs
    path_crumbs(@dirname)
  end

  def get_binding
    binding
  end
end

class Crumb
  attr_reader :url, :name
  def initialize(args)
    @url = args[:url]
    @name = args[:name]
  end
end

visit(SRC_DIR)
