#BiocMaintainerShiny <- function(...) {

library(shiny); library(jsonlite); library(DT); library(shinyjs)


    ui <- fluidPage(
        titlePanel(
            windowTitle = "Bioc Maintainer Table",
            title = div(
                h1("Bioconductor Maintainer Table"),
                h4("List Package Maintainers and Email Status")
            )
        ),      
        sidebarLayout(
            sidebarPanel(
                h4("Optional Columns"),
                checkboxGroupInput(
                    "show_cols", "Select columns to display:",
                    choices = c(
                        "consent_date",
                        "is_email_valid",
                        "bounce_type",
                        "bounce_subtype",
                        "smtp_status",
                        "diagnostic_code"
                    ),
                    selected = character(0)  # Default: none selected
                ),
                width = 3
            ),
            
            mainPanel(
                DT::dataTableOutput("maintainers_table"),
                width = 9
            )
        )
    )
    
    server <- function(input, output, session) {
        data <- reactive({
            url <- "http://127.0.0.1:4567/download-maintainer-db"
            jsonlite::fromJSON(url)
        })
        
        output$maintainers_table <- DT::renderDataTable({
            df <- data()
            all_cols <- colnames(df)
            
            optional_cols <- c(
                "consent_date",
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
    }
    
    shinyApp(ui, server   #, ...
         )    


#}

