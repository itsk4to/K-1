export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname !== "/k1") {
      return new Response("Not Found", {
        status: 404
      });
    }

    const token = url.searchParams.get("token");

    if (!token || token !== env.K1_TOKEN) {
      return new Response("Unauthorized", {
        status: 401
      });
    }

    return new Response("K-1 access granted", {
      status: 200
    });
  }
};
