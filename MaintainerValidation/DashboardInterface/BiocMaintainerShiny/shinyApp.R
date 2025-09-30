#BiocMaintainerShiny <- function(...) {

library(shiny); library(jsonlite); library(DT); library(shinyjs); library(shinythemes)


    ui <- fluidPage(

        theme = shinytheme("simplex"),
        shinyjs::useShinyjs(),
        tags$head(
                 tags$style(
                          HTML("
                            #main-title { color: #076570; font-weight: bold; }
                            #sub-title { color: #87B13F; font-size:18px }
                            .sidebar { padding: 10px; background-color: #f9f9f9; }
                            #sidebar_button i.fa-bars{ color: #076570 !important; font-size: 24px;}
                          ")
                      )
             ),
        
        titlePanel(
            windowTitle = "Bioc Maintainer Table",
            title = div(
                h1("Bioconductor Maintainer Table", id="main-title"),
                h3("List Package Maintainers and Email Status", id="sub-title")
            )
        ),

        navbarPage(
            title = actionLink("sidebar_button", label = NULL, icon = icon("bars")),
            id = "navbarID",

            tabPanel(
                title = h4("Maintainer Table"),
                sidebarLayout(
                    div(class="sidebar",
                        sidebarPanel(
                            div(
                                id="optional_columns",
                                h4("Optional Columns"),
                                checkboxGroupInput(
                                    "show_cols", "Select columns to display:",
                                    choices = c(
                                        "consent_date",
                                        "needs_consent",
                                        "email_status",
                                        "is_email_valid",
                                        "bounce_type",
                                        "bounce_subtype",
                                        "smtp_status",
                                        "diagnostic_code"
                                    ),
                                    selected = character(0)  # Default: none selected
                                ),
                                width = 3
                            )
                        )),
            
                    mainPanel(
                        DT::dataTableOutput("maintainers_table"),
                        width = 9
                    )
                )
            ),

            
            tabPanel(
                title = h4("About"),
                fluidRow(
                    column(
                        width = 10, offset = 1,
                        h3("About This App"),
                        p("This application displays Bioconductor package maintainer info."),
                        p("You can toggle visibility of optional metadata fields using the sidebar.")
                    )
                )
            )
        )
    )
    
    server <- function(input, output, session) {

        observeEvent(input$toggle_opts, {
            shinyjs::toggle("optional_columns")
        })

        
        data <- reactive({
            url <- "http://127.0.0.1:4567/download-maintainer-db"
            df <- jsonlite::fromJSON(url)

            if ("is_email_valid" %in% names(df)) {
                df$is_email_valid <- as.logical(df$is_email_valid)
            }
            
            if ("consent_date" %in% names(df)) {
                df$consent_date <- as.Date(df$consent_date)  # Ensure it's Date type
                one_year_ago <- Sys.Date() - 365
                df$needs_consent <- df$consent_date < one_year_ago
            } else {
                df$needs_consent <- NA  # Handle missing column gracefully
            }
            
            df            
        })
        
        output$maintainers_table <- DT::renderDataTable({
            df <- data()
            
            if (all(c("needs_consent", "consent_date") %in% colnames(df))) {
                col_order <- colnames(df)
                col_order <- setdiff(col_order, "needs_consent")
                consent_pos <- match("consent_date", col_order)
                col_order <- append(col_order, "needs_consent", after = consent_pos)
                df <- df[, col_order]
            }
            
            all_cols <- colnames(df)
            
            optional_cols <- c(
                "consent_date",
                "needs_consent",
                "email_status",
                "is_email_valid",
                "bounce_type",
                "bounce_subtype",
                "smtp_status",
                "diagnostic_code"
            )
            
            to_hide <- setdiff(optional_cols, input$show_cols)
            hide_indices <- which(all_cols %in% to_hide) - 1
            
            DT::datatable(
                df,
                filter = 'top',
                rownames = FALSE,
                options = list(
                    pageLength = 10,
                    autoWidth = TRUE,
                    columnDefs = list(
                        list(visible = FALSE, targets = hide_indices)
                    )
                )
            )
        })
        observeEvent(input$sidebar_button,{
            shinyjs::toggle(selector = ".sidebar")
        })        
    }
    
    shinyApp(ui, server   #, ...
         )    


#}

