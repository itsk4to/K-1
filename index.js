const OWNER = "itsk4to";
const REPO = "K-1";
const FILE = "script";
const BRANCH = "main";

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Chỉ cho phép endpoint /k1
    if (url.pathname !== "/k1") {
      return new Response("Not Found", { status: 404 });
    }

    // Kiểm tra K1_TOKEN
    const token = url.searchParams.get("token");

    if (!token || token !== env.K1_TOKEN) {
      return new Response("Unauthorized", { status: 401 });
    }

    // Lấy shader từ repo GitHub Private
    const githubUrl =
      `https://api.github.com/repos/${OWNER}/${REPO}/contents/${FILE}?ref=${BRANCH}`;

    const githubResponse = await fetch(githubUrl, {
      headers: {
        "Authorization": `Bearer ${env.GITHUB_TOKEN}`,
        "Accept": "application/vnd.github+json",
        "User-Agent": "K-1-Worker"
      }
    });

    if (!githubResponse.ok) {
      return new Response("Shader unavailable", { status: 502 });
    }

    const data = await githubResponse.json();

    if (!data.content) {
      return new Response("Invalid shader file", { status: 502 });
    }

    // GitHub trả file dưới dạng Base64
    const shader = atob(data.content.replace(/\n/g, ""));

    return new Response(shader, {
      status: 200,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "no-store"
      }
    });
  }
};
