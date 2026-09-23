package com.thk.mdview

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ThemeConfigurationTest {
    @Test fun mermaidUsesConfiguredPaletteAndFontSize() {
        val theme = THKMDTheme.Default.copy(bodyFontSizeSp = 23f,
            bodyTextColor = 0xFF123456.toInt(), codeBackgroundColor = 0xFFABCDEF.toInt())
        val variables = theme.mermaidConfiguration().getJSONObject("themeVariables")
        assertEquals("23.0px", variables.getString("fontSize"))
        assertEquals("rgba(18,52,86,1.0)", variables.getString("primaryTextColor"))
        assertEquals("rgba(171,205,239,1.0)", variables.getString("primaryColor"))
    }
}
