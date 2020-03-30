# @summary Configures Netbox and gunicorn
#
# Configures Netbox and gunicorn, and load the database schema.
#
# @param user
#   The user owning the Netbox installation files, and running the
#   service.
#
# @param group
#   The group owning the Netbox installation files, and running the
#   service.
#
# @param install_root
#   The root directory of the netbox installation.
#
# @param allowed_hosts
#   Array of valid fully-qualified domain names (FQDNs) for the NetBox server. NetBox will not permit write
#   access to the server via any other hostnames. The first FQDN in the list will be treated as the preferred name.
#
# @param database_name
#   Name of the PostgreSQL database. If handle_database is true, then this database
#   gets created as well. If not, then it is only used by the application, and needs to exist.
#
# @param database_user
#   Name of the PostgreSQL database user. If handle_database is true, then this database user
#   gets created as well. If not, then it is only used by the application, and needs to exist.
#
# @param database_password
#   Name of the PostgreSQL database password. If handle_database is true, then this database password
#   gets created as well. If not, then it is only used by the application, and needs to exist.
#
# @param database_host
#   Hostname where the PostgreSQL database resides.
#
# @param database_port
#   PostgreSQL database port. NB! The PostgreSQL database that is made when using handle_database
#   does not support configuring a non-standard port. So change this parameter only if using 
#   separate PostgreSQL DB with non-standard port. Defaults to 5432.
#
# @param database_conn_max_age
#   Database max connection age in seconds. Defaults to 300.
#
# @param redis_options
#   Options used against redis. Customize to fit your redis installation. Use default values
#   if using the redis bundled with this module.
#
# @param email_options
#   Options used for sending email.
#
# @param secret_key
#   A random string of letters, numbers and symbols that Netbox needs.
#   This needs to be supplied, and should be treated as a secret. Should
#   be at least 50 characters long.
#   
# @param banner_top
#   Text for top banner on the Netbox webapp
#
# @param banner_bottom
#   Text for bottom banner on the Netbox webapp
#
# @param banner_login
#   Text for login banner on the Netbox webapp
#
# @param base_path
#   Base URL path if accessing NetBox within a directory.
#   For example, if installed at http://example.com/netbox/, set: BASE_PATH = 'netbox/'
#
# @param debug
#   Set to True to enable server debugging. WARNING: Debugging introduces a substantial performance penalty and may reveal
#   sensitive information about your installation. Only enable debugging while performing testing. Never enable debugging
#   on a production system.
#
# @param enforce_global_unique
#   Enforcement of unique IP space can be toggled on a per-VRF basis. To enforce unique IP space within the global table
#   (all prefixes and IP addresses not assigned to a VRF), set ENFORCE_GLOBAL_UNIQUE to True.
#
# @example
#   include netbox::config
class netbox::config (
  String $user,
  String $group,
  Stdlib::Absolutepath $install_root,
  Array[Stdlib::Host] $allowed_hosts,
  String $database_name,
  String $database_user,
  String $database_password,
  Stdlib::Host $database_host,
  Integer $database_port,
  Integer $database_conn_max_age,
  Hash $redis_options,
  Hash $email_options,
  String $secret_key,
  Array $admins,
  String $banner_top,
  String $banner_bottom,
  String $banner_login,
  String $base_path,
  Boolean $debug,
  Boolean $enforce_global_unique,
  Boolean $login_required,
  Array $exempt_view_permissions,
) {
  $should_create_superuser = false;
  $software_directory = "${install_root}/netbox"
  $venv_dir = "${software_directory}/venv"
  $gunicorn_file = "${software_directory}/gunicorn.py"

  $gunicorn_settings = {
    port                => 8001,
    workers             => 5,
    threads             => 3,
    timeout             => 120,
    max_requests        => 5000,
    max_requests_jitter => 500,
  }

  file { $gunicorn_file:
    content => epp('netbox/gunicorn.py.epp', $gunicorn_settings),
    owner   => $user,
    group   => $group,
    mode    => '0644',
  }

  $config_file = "${software_directory}/netbox/netbox/configuration.py"

  file { $config_file:
    content      => epp('netbox/configuration.py.epp', {
      'allowed_hosts'           => $allowed_hosts,
      'database_name'           => $database_name,
      'database_user'           => $database_user,
      'database_password'       => $database_password,
      'database_host'           => $database_host,
      'database_port'           => $database_port,
      'database_conn_max_age'   => $database_conn_max_age,
      'redis_options'           => $redis_options,
      'email_options'           => $email_options,
      'secret_key'              => $secret_key,
      'admins'                  => $admins,
      'banner_top'              => $banner_top,
      'banner_bottom'           => $banner_bottom,
      'banner_login'            => $banner_login,
      'base_path'               => $base_path,
      'debug'                   => $debug,
      'enforce_global_unique'   => $enforce_global_unique,
      'exempt_view_permissions' => $exempt_view_permissions,
      'login_required'          => $login_required,

    }),
    owner        => $user,
    group        => $group,
    mode         => '0644',
    validate_cmd => "${venv_dir}/bin/python -m py_compile %",
  }

  Exec {
    cwd         => $software_directory,
    path        => [ "${venv_dir}/bin", '/usr/bin', '/usr/sbin' ],
    environment => ["VIRTUAL_ENV=${venv_dir}"],
    provider    => shell,
    user        => $user,
  }

  exec { 'database migration':
    onlyif  => "${venv_dir}/bin/python3 netbox/manage.py showmigrations | grep '\[ \]'",
    command => "${venv_dir}/bin/python3 netbox/manage.py migrate --no-input",
    require => File[$config_file];
  }
  exec { 'collect static files':
    command     => "${venv_dir}/bin/python3 netbox/manage.py collectstatic --no-input",
    subscribe   => File[$config_file],
    refreshonly => true,
  }
}
