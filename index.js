const OWNER = "itsk4to";
const REPO = "K-1";
const FILE = "scripts";
const BRANCH = "main";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Chỉ cho phép /k1
    if (url.pathname !== "/k1") {
      return new Response("Not Found", {
        status: 404
      });
    }

    // Kiểm tra token của loader
    const token = url.searchParams.get("token");

    if (!token || token !== env.K1_TOKEN) {
      return new Response("Unauthorized", {
        status: 401
      });
    }

    // GitHub API
    const githubUrl =
      `https://api.github.com/repos/${OWNER}/${REPO}/contents/${FILE}?ref=${BRANCH}`;

    const githubResponse = await fetch(githubUrl, {
      headers: {
        "Authorization": `Bearer ${env.GITHUB_TOKEN}`,
        "Accept": "application/vnd.github+json",
        "User-Agent": "K-1-Worker"
      }
    });

    // Hiển thị lỗi GitHub để debug
    if (!githubResponse.ok) {
      const errorText = await githubResponse.text();

      return new Response(
        `GitHub error ${githubResponse.status}\n${errorText}`,
        {
          status: 502,
          headers: {
            "Content-Type": "text/plain; charset=utf-8"
          }
        }
      );
    }

    const data = await githubResponse.json();

    // Kiểm tra GitHub response
    if (!data.content) {
      return new Response("GitHub returned no file content", {
        status: 502
      });
    }

    // GitHub API trả file dạng Base64
    const shader = atob(
      data.content.replace(/\s/g, "")
    );

    // Trả shader cho client
    return new Response(shader, {
      status: 200,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "no-store"
      }
    });
  }
};
