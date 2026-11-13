<?xml version="1.0"?>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:output method="html" encoding="UTF-8"/>
  <xsl:template match="/"><html><body><h1>Order</h1><table>
    <xsl:for-each select="order/item"><tr><td><xsl:value-of select="name"/></td><td><xsl:value-of select="quantity * 2"/></td></tr></xsl:for-each>
  </table></body></html></xsl:template>
</xsl:stylesheet>
