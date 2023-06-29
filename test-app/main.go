package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
)

func main() {
	http.HandleFunc("/", func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprintf(w, `
<!DOCTYPE html>
<html>
    <body>
        <h1>Secrets from Vault</h1>
        <p>TEST_USER = %s</p>
        <p>TEST_PASSWORD = %s</p>
    </body>
</html>`,
			os.Getenv("TEST_USER"),
			os.Getenv("TEST_PASSWORD"),
		)
	})

	log.Println("listening on :7777")

	if err := http.ListenAndServe(":7777", nil); err != nil {
		log.Fatal(err)
	}
}
