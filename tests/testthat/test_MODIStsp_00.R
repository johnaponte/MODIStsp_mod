message("MODIStsp Test 0: Gracefully fail on input problems")
test_that(
  "Tests on MODIStsp", {
    skip_on_cran()
    skip_on_travis()

    # wrong path or non-existing opts_file
    expect_error(expect_warning(MODIStsp(opts_file = "", gui = FALSE),
                                "Processing Options file not found"))

    expect_error(expect_warning(MODIStsp(opts_file = "", gui = TRUE),
                                "The specified `.json` options file was not
                                found"))
    # provided options file is not a MODIStsp json options file
    expect_error(MODIStsp(
      opts_file = system.file("ExtData", "MODIStsp_ProdOpts.xml.zip",
                                 package = "MODIStsp.mod"),
      gui = FALSE), "Unable to read the provided options")

    # # Credentials for earthdata login for http download are wrong
    # # TEST DEACTIVATED because, in some cases, downloading HDFs is possible
    # # even without autentication
    # expect_error(MODIStsp(
    #   opts_file = system.file("testdata/test05a.json",
    #                              package = "MODIStsp.mod"), over,
    #   gui = FALSE, n_retries = 2), "Username and/or password are not valid")
  })
