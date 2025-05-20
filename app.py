from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/")
def home():
    return jsonify(message="Hello Anurag -Dockered now! at 12:19 ")

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=4908)
