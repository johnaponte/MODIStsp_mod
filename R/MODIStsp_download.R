#' @title MODIStsp download function
#' @description Internal function dealing with download of MODIS hdfs from
#'  http remote server for a given date.
#' @param modislist `character array` List of MODIS images to be downloaded for
#'  the selected date (as returned from `get_mod_filenames`). Can be a single
#'  image, or a list of images in case different tiles are needed!
#' @param out_folder_mod `character` Folder where the hdfs are to be stored
#' @param download_server `character ["http"]` Server to be used.
#' @param http `character` Address of the http server for the selected product.
#' @param n_retries `numeric` Max number of retry attempts on download. If
#'  download fails more that n_retries times consecutively, abort
#' @param date_dir `character array` Sub-folder where the different images
#'  can be found (element of the list returned from `get_mod_dirs`, used in case
#'  of http download to generate the download addresses).
#' @param use_aria `logical` if TRUE, download using aria2c
#' @param year `character` Acquisition year of the images to be downloaded
#' @param DOY `character array` Acquisition doys of the images to be downloaded
#' @param user `character` Username for http download. Not used as BASIC authentication does not work
#' @param password `character` Password for http download Not used as BASIC authentication does not work
#' @param sens_sel `character ["terra" | "aqua"]` Selected sensor.
#' @param date_name `character` Date of acquisition of the images to be downloaded.
#' @param gui `logical` Indicates if on an interactive or non-interactive execution
#'  (only influences where the log messages are sent).
#' @param verbose `logical` If FALSE, suppress processing messages, Default: TRUE
#' @return The function is called for its side effects
#' @rdname MODIStsp_download
#' @author Lorenzo Busetto, phD (2014-2017)
#' @author Luigi Ranghetti, phD (2015)
#' @importFrom curl curl curl_download curl_fetch_disk new_handle
#' @importFrom xml2 as_list read_xml

MODIStsp_download <- function(modislist,
                              out_folder_mod,
                              download_server,
                              http,
                              n_retries,
                              use_aria,
                              date_dir,
                              year,
                              DOY,
                              user,
                              password,
                              sens_sel,
                              date_name,
                              gui,
                              verbose) {

  # Check for .netrc file existence
  if (!file.exists("~/.netrc")) {
    stop("BASIC authentication does not work. Create a .netrc file. See https://urs.earthdata.nasa.gov/documentation for details.")
  }

  # Cycle on the different files to download for the current date
  for (file in seq_along(modislist)) {
    modisname <- modislist[file]

    #   ________________________________________________________________________
    # Try to retrieve the file size of the remote HDF so that if a local    ####
    # file exists but size is different it can be redownloaded
    #
    local_filename  <- file.path(out_folder_mod, modisname)
    if (file.exists(local_filename))  {
      local_filesize <- file.info(local_filename)$size
    } else {
      local_filesize <- 0
    }

    if (download_server == "http") {
      remote_filename <- paste0(http, date_dir, "/", modisname)
    }
    if (download_server == "offline") {
      remote_filename <- NA
    }
    success <- FALSE
    # On http download, try to catch size information from xml file ----
    if (download_server == "http") {
      while (success == FALSE) {

        xml_url <- paste0(remote_filename, ".xml")
        xml_tempfile <- tempfile(fileext = ".xml")
        try({
          curl::curl_download(url = xml_url, destfile = xml_tempfile, handle = curl::new_handle(netrc = 1))
          size_string <- xml2::read_xml(xml_tempfile)
        }, silent = TRUE)

        # if user/password are not valid, notify
        if (inherits(size_string, "try-error") || is.null(size_string)) {
          stop("Username and/or password are not valid. Please provide
             valid ones!")
        }

        if (!is.null(size_string)) {
          remote_filesize <- as.integer(
            xml2::as_list(size_string)[["GranuleMetaDataFile"]][["GranuleURMetaData"]][["DataFiles"]][["DataFileContainer"]][["FileSize"]] #nolint
          )
          success <- TRUE
        } else {
          # If the remote xml file was not accessible, n_retries times,
          # retry or abort
          stop("[", date(), "] Error: http server seems to be down! Please retry ", #nolint
               "Later!", .call = FALSE)
        }
      }
    } else {

      # On offline mode, don't perform file size check ----
      remote_filesize <- local_filesize
    }

    #   ________________________________________________________________________
    #   Download required HDF images                                        ####
    #   (If HDF not existing locally, or existing with different size)
    #

    if (!file.exists(local_filename) | local_filesize != remote_filesize) {

      # update messages
      mess_text <- paste("Downloading", sens_sel, "Files for date:",
                         date_name, ":", which(modislist == modisname),
                         "of: ", length(modislist))
      # Update progress window
      process_message(mess_text, verbose)
      success <- FALSE
      attempt <- 0
      #  _______________________________________________________________________
      #  while loop: try to download n_retries times  ####
      while (attempt < n_retries) {

        if (download_server == "http") {
          # http download - aria
          if (use_aria == TRUE) {
            aria_string <- paste0(
              Sys.which("aria2c"), " -x 6 -d ",
              dirname(local_filename),
              " -o ", basename(remote_filename),
              " ", remote_filename,
              " --allow-overwrite --file-allocation=none --retry-wait=2",
              " --http-user=", user,
              " --http-passwd=", password)

            # intern=TRUE for Windows, FALSE for Unix
            download <- try(system(aria_string,
                                   intern = Sys.info()["sysname"] == "Windows"))
          } else {
            # http download - curl with .netrc authentication
            handle <- curl::new_handle(netrc = 1)
            download <- try(curl::curl_fetch_disk(url = remote_filename, path = local_filename, handle = handle))
            # download <- try(httr::GET(remote_filename,
            #                           httr::authenticate(user, password, type = "any"),
            #                           # httr::progress(),
            #                           httr::write_disk(local_filename,
            #                                            overwrite = TRUE)))
          }
        }

        # Check for errors on download try
        if (inherits(download, "try-error") |
            !is.null(attr(download, "status"))) {
          attempt <- attempt + 1
          if (verbose) message("[", date(), "] Download Error - Retrying...")
          unlink(local_filename)  # On download error, delete incomplete files
          Sys.sleep(1)    # sleep for a while....
        } else {
          if (download_server == "http" & use_aria == FALSE) {

            if (download$status_code != 200 || file.size(local_filename) == 0) {
              # on error, delete last HDF file (to be sure no incomplete
              # files are left behind and send message)
              if (verbose) {
                message("[", date(), "] Download Error - Retrying...")
              }
              unlink(local_filename)
            }
          }
        }
        # final check on local file size: Only exit if local file size equals
        # remote filesize to  prevent problems on incomplete download!
        local_filesize <- file.info(local_filename)$size
        if (local_filesize == remote_filesize & !is.na(local_filesize)) {
          # on success, bump attempt number so to exit the while cycle
          attempt <- n_retries + 1
          success <- TRUE
        } else {
          attempt <- attempt + 1
        }
      }
      if (attempt == n_retries & success == FALSE) {
          unlink(local_filename)
          stop("[", date(), "] Error: server seems to be down! Please retry ",
               "Later!")

      }
    } else {
      mess_text <- paste("HDF File:", modisname,
                         "already exists on your system. Skipping download!")
      process_message(mess_text, verbose)
    }
  }
}
