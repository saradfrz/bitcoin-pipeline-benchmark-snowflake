CREATE API INTEGRATION IF NOT EXISTS github_di_pipe_eng
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/saradfrz/di-pipe-eng.git')
    API_USER_AUTHENTICATION = (TYPE = SNOWFLAKE_GITHUB_APP)
    ENABLED = TRUE;