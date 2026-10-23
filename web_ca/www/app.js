const API = "/api";


function $(id)
{
    return document.getElementById(id);
}

function initTheme() {
    const saved = localStorage.getItem("ca-manager-theme");
    if (saved === "dark") document.body.classList.add("dark");
    const toggle = $("theme-toggle");
    if (toggle) toggle.addEventListener("click", () => {
        document.body.classList.toggle("dark");
        localStorage.setItem("ca-manager-theme", document.body.classList.contains("dark") ? "dark" : "light");
        const icon = $("theme-icon");
        if (icon) icon.textContent = document.body.classList.contains("dark") ? "☀" : "☾";
    });
    const icon = $("theme-icon");
    if (icon) icon.textContent = document.body.classList.contains("dark") ? "☀" : "☾";
}

function showPage(pageId, button)
{
    document.querySelectorAll(".page").forEach(page => {
        const active = page.id === pageId;
        page.hidden = !active;
        page.classList.toggle("active", active);
    });
    document.querySelectorAll(".tab").forEach(tab => tab.classList.toggle("active", tab.dataset.page === pageId));
    if (button) button.classList.add("active");
}

function renderClientList(container, clients)
{
    if (!container) return;
    container.replaceChildren();
    if (!Array.isArray(clients) || clients.length === 0) {
        const empty = document.createElement("p");
        empty.className = "muted";
        empty.textContent = "Keine Client-Liste von der API geliefert.";
        container.appendChild(empty);
        return;
    }
    clients.forEach(item => {
        const name = typeof item === "string" ? item : (item.name ?? item.cn ?? item.commonName ?? "Unbekannter Client");
        const row = document.createElement("div");
        row.className = "client-row";
        row.setAttribute("role", "listitem");
        const label = document.createElement("span");
        label.textContent = name;
        row.appendChild(label);
        if (typeof item === "object") {
            const detail = document.createElement("span");
            detail.className = "muted";
            const parts = [];
            if (item.status) parts.push(item.status);
            if (typeof item.days_remaining === "number") parts.push(item.days_remaining < 0 ? `seit ${Math.abs(item.days_remaining)} Tagen abgelaufen` : `${item.days_remaining} Tage`);
            if (item.profile === true) parts.push("Profil vorhanden");
            if (item.profile === false) parts.push("Profil fehlt");
            detail.textContent = parts.join(" · "); row.appendChild(detail);
            if (item.status) {
                const status = document.createElement("span");
                const value = String(item.status).toUpperCase();
                status.className = "badge " + (value === "VALID" ? ((typeof item.days_remaining === "number" && item.days_remaining <= 30) ? "warn" : "ok") : "error");
                status.textContent = value; row.appendChild(status);
            }
        }
        container.appendChild(row);
    });
}

async function pullClientList(origin = "dashboard")
{
    const button = origin === "ca" ? $("ca-refresh-clients-btn") : $("refresh-clients-btn");
    const oldText = button ? button.textContent : "";
    if (button) { button.disabled = true; button.textContent = "Prüfe Clients …"; }
    try {
        const response = await fetch(`${API}/clients`, { cache: "no-store" });
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const result = await response.json();
        if (result.success === false) throw new Error(result.error || "Crawler meldet einen Fehler");
        const clients = Array.isArray(result) ? result : (result.clients ?? result.clientList ?? []);
        renderClientList($("dashboard-client-list"), clients);
        renderClientList($("clients-page-list"), clients);
        renderClientList($("ca-dashboard-client-list"), clients);
        if (typeof result.count === "number") {
            if ($("dashboard-client-count")) $("dashboard-client-count").textContent = result.count;
            if ($("ca-dashboard-client-count")) $("ca-dashboard-client-count").textContent = result.count;
            if ($("client-count")) $("client-count").textContent = result.count;
        }
        const summary = result.summary;
        if (summary) {
            const text = `Gültig: ${summary.valid ?? 0} · Läuft bald ab: ${summary.expiring ?? 0} · Abgelaufen: ${summary.expired ?? 0} · Widerrufen: ${summary.revoked ?? 0} · Profil fehlt: ${summary.missing_profile ?? 0}`;
            if ($("client-list-summary")) $("client-list-summary").textContent = text;
            if ($("ca-client-list-summary")) $("ca-client-list-summary").textContent = text;
        }
        setActivityLog(`Client-Crawler abgeschlossen: ${clients.length} Client(s) gefunden.`);
    } catch (error) {
        setActivityLog(`Client-Crawler fehlgeschlagen: ${error.message}`);
        console.error("Client-Crawler:", error);
    } finally {
        if (button) { button.disabled = false; button.textContent = oldText || "Client-Liste aktualisieren"; }
    }
}



async function loadStatus()
{
    try
    {
        let response =
            await fetch(`${API}/status`);


        let data =
            await response.json();


        let ca =
            $("ca-status");


        if(data.ca)
        {
            ca.innerText = "AKTIV";
            ca.className = "badge ok";
        }
        else
        {
            ca.innerText = "NICHT INITIALISIERT";
            ca.className = "badge warn";
        }


        const count = typeof data.clients === "number" ? data.clients :
            (Array.isArray(data.clients) ? data.clients.length : (data.clientCount ?? 0));
        if ($("client-count")) $("client-count").innerText = count;
        if ($("dashboard-client-count")) $("dashboard-client-count").innerText = count;
        if ($("ca-dashboard-client-count")) $("ca-dashboard-client-count").innerText = count;
        if ($("dashboard-ca-status")) {
            $("dashboard-ca-status").innerText = data.ca ? "AKTIV" : "NICHT INITIALISIERT";
            $("dashboard-ca-status").className = "status " + (data.ca ? "ok" : "warn");
        }
        if ($("ca-dashboard-ca-status")) {
            $("ca-dashboard-ca-status").innerText = data.ca ? "AKTIV" : "NICHT INITIALISIERT";
            $("ca-dashboard-ca-status").className = "status " + (data.ca ? "ok" : "warn");
        }
        if ($("ca-page-status")) $("ca-page-status").innerText = data.ca ? "AKTIV" : "NICHT INITIALISIERT";

        if(data.host)
        {
            $("server-host").innerText = data.host;
            $("server-port").innerText = data.port ?? "-";
            $("server-crypto").innerText = data.crypto ?? "-";
            if ($("dashboard-server-host")) $("dashboard-server-host").innerText = data.host;
            if ($("dashboard-server-detail")) $("dashboard-server-detail").innerText = `Port: ${data.port ?? "-"} · Crypto: ${data.crypto ?? "-"}`;
            if ($("ca-dashboard-server-host")) $("ca-dashboard-server-host").innerText = data.host;
            if ($("ca-dashboard-server-detail")) $("ca-dashboard-server-detail").innerText = `Port: ${data.port ?? "-"} · Crypto: ${data.crypto ?? "-"}`;
        }


    }
    catch(error)
    {
        if ($("ca-status")) {
            $("ca-status").innerText = "API FEHLER";
            $("ca-status").className = "badge error";
        }

        console.error(error);
    }
}





function showCASetup()
{
    let box = $("setup");


    box.style.display =
        box.style.display === "none"
        ? "block"
        : "none";
}






async function createCA()
{

    let form =
        new URLSearchParams(
        {
            cn: cn.value,
            org: org.value,
            ou: ou.value,
            email: email.value,

            country: country.value,
            province: province.value,
            city: city.value,

            host: host.value,
            port: port.value,

            algo: algo.value,
            digest: digest.value,
            dh: dh.value
        });



    await fetch(
        `${API}/save-config`,
        {
            method:"POST",
            body:form
        }
    );



    log(
        "CA Build gestartet...\n\n"
    );




await fetch(
    `${API}/build-ca`
);



let timer =
    setInterval(
        async () =>
        {

            let txt =
                await fetchText(
                    "/build-log"
                );


            log(txt);



            scrollActivityLogs();



            if(
                txt.includes("CA READY")
            )
            {

                clearInterval(timer);


                await loadStatus();



                $("setup").style.display =
                    "none";

            }

        },
        1000
    );


}






async function newClient()
{
    const name = $("client-name").value.trim();
    if (!name) return alert("Client Name fehlt");

    setActivityLog(`Erzeuge Client und TCP/UDP/Connect-Profile: ${name}`);
    const result = await fetchText(`/client-create?name=${encodeURIComponent(name)}`);
    setActivityLog(result);
    await loadStatus();
    await pullClientList();
}






async function clientInfo()
{
    let name =
        $("client-name").value;


    if(!name)
        return alert("Client Name fehlt");


    log(
        await fetchText(
            `/client-info?name=${encodeURIComponent(name)}`
        )
    );
}






async function revokeClient()
{
    let name =
        $("client-name").value;


    if(!name)
        return alert("Client Name fehlt");



    if(
        !confirm(
            `${name} wirklich sperren?`
        )
    )
    {
        return;
    }



    log(
        await fetchText(
            `/client-revoke?name=${encodeURIComponent(name)}`
        )
    );


    await loadStatus();
}







async function recreateClient()
{
    let name =
        $("client-name").value;


    if(!name)
        return alert("Client Name fehlt");



    log(
        await fetchText(
            `/client-recreate?name=${encodeURIComponent(name)}`
        )
    );


    await loadStatus();

}







async function destroyCA()
{

    if(
        !$("destroy-confirm").checked
    )
    {
        return alert(
            "Bitte bestätigen"
        );
    }



    log(
        await fetchText(
            "/destroy-ca"
        )
    );


    $("destroy-confirm").checked =
        false;


    await loadStatus();

}






async function exportServer()
{
    const button = document.querySelector('button[onclick="exportServer()"]');
    const oldText = button ? button.textContent : "";
    if (button) { button.disabled = true; button.textContent = "Export läuft …"; }
    log("SERVER-EXPORT: Export wird gestartet …");

    try {
        const response = await fetch(`${API}/server-export`, { method: "POST", cache: "no-store" });
        const text = (await response.text()).trim();
        if (!response.ok) {
            throw new Error(text || `HTTP ${response.status}`);
        }
        log(text || "SERVER-EXPORT: Erfolgreich abgeschlossen.");
    } catch (error) {
        log(`SERVER-EXPORT FEHLER: ${error.message || error}`);
    } finally {
        if (button) { button.disabled = false; button.textContent = oldText; }
    }
}



function backupCA()
{
    location.href =
        `${API}/backup-ca`;
}



function downloadClient(mode)
{
    const name = $("client-name").value.trim();
    if (!name) return alert("Client Name fehlt");
    if (!["tcp", "udp", "connect"].includes(mode)) return alert("Ungültiger Profiltyp");
    location.href = `${API}/client-download?name=${encodeURIComponent(name)}&mode=${encodeURIComponent(mode)}`;
}






async function fetchText(endpoint)
{

    let r =
        await fetch(
            API + endpoint
        );


    return await r.text();

}



function setActivityLog(text)
{
    [$("logbox")].forEach(box => {
        if (box) box.textContent = text;
    });
}

function scrollActivityLogs()
{
    [$("logbox")].forEach(box => {
        if (box) box.scrollTop = box.scrollHeight;
    });
}

function log(text)
{
    setActivityLog(text);
}






window.addEventListener(
    "load",
    () =>
    {
        initTheme();
        loadStatus();

        setInterval(
            loadStatus,
            5000
        );
    }
);
